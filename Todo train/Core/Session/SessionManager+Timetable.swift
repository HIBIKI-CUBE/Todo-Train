//
//  SessionManager+Timetable.swift
//  Todo train
//

import Foundation
import SwiftData
import TodoTrainSync
import UserNotifications

/// 運行開始の盤に出す予定。着発はダイヤ、通過は掲示か、今回だけ外した手入力。
nonisolated struct OpeningTimetableEntry: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case stop(blockID: UUID)
        case passNotice(occurrenceID: String)
        case passManual(blockID: UUID)
    }

    var kind: Kind
    var title: String
    var startsAt: Date
    var endsAt: Date

    var id: String {
        switch kind {
        case .stop(let blockID):
            return "stop:\(blockID.uuidString)"
        case .passNotice(let occurrenceID):
            return "notice:\(occurrenceID)"
        case .passManual(let blockID):
            return "pass:\(blockID.uuidString)"
        }
    }

    var stops: Bool {
        if case .stop = kind { return true }
        return false
    }

    var interval: TimetableOpeningInterval {
        TimetableOpeningInterval(startsAt: startsAt, endsAt: endsAt)
    }
}

/// 着発した予定だけから組んだ、盤の時間割・運転状況・ただいま・LOAD。
nonisolated struct OpeningTimetableBoard: Equatable, Sendable {
    var entries: [OpeningTimetableEntry]
    var range: TimetableRange
    var bands: [RunStatusBand]
    var reading: RunStatusNow
    var next: RunStatusNext
    var load: ServiceLoadSnapshot
    var isTwentyFourHour: Bool

    static func make(
        entries: [OpeningTimetableEntry],
        now: Date,
        isTwentyFourHour: Bool,
        referenceDay: Date,
        ticketsAboveCutoff: [ServiceLoadTicket],
        calendar: Calendar
    ) -> OpeningTimetableBoard {
        let scheduled = entries.map(\.interval)
        let adopted = entries.filter(\.stops).map(\.interval)
        let range = TimetableRangeLogic.compute(
            scheduledBlocks: scheduled,
            referenceDay: referenceDay,
            isTwentyFourHour: isTwentyFourHour,
            calendar: calendar
        )
        let bands = RunStatusLogic.bands(range: range, adoptedBlocks: adopted)
        return OpeningTimetableBoard(
            entries: entries,
            range: range,
            bands: bands,
            reading: RunStatusLogic.nowReading(now: now, range: range, bands: bands),
            next: RunStatusLogic.nextMarkers(now: now, adoptedBlocks: adopted),
            load: ServiceLoadLogic.compute(
                now: now,
                range: range,
                adoptedBlocks: adopted,
                ticketsAboveCutoff: ticketsAboveCutoff
            ),
            isTwentyFourHour: isTwentyFourHour
        )
    }
}

extension SessionManager {
    func timetableFit(at now: Date? = nil) -> TimetableFitSnapshot {
        let now = now ?? clock.now
        let blocks = fetchActiveTimetableBlocks().map {
            TimetableFitBlock(id: $0.id, title: $0.title, startsAt: $0.startsAt, endsAt: $0.endsAt)
        }
        let budgetEndsAt: Date?
        if let session = activeSession, session.isOpen, !session.isPaused {
            let remaining = session.remainingSeconds(at: now)
            budgetEndsAt = remaining > 0 ? now.addingTimeInterval(remaining) : nil
        } else {
            budgetEndsAt = nil
        }
        return TimetableFit.snapshot(
            blocks: blocks,
            notices: unadoptedNoticeBlocks(at: now),
            now: now,
            budgetEndsAt: budgetEndsAt
        )
    }

    func applyTimetableEffects(now: Date) {
        let blocks = fetchActiveTimetableBlocks().map {
            TimetableGuardBlock(id: $0.id, startsAt: $0.startsAt, endsAt: $0.endsAt, isCancelled: $0.isCancelled)
        }
        let openModel = fetchOpenTimetableGuard()
        let open = openModel.map {
            TimetableOpenGuard(
                id: $0.id,
                sessionID: $0.sessionID,
                blockID: $0.blockID,
                notifiedAt: $0.notifiedAt,
                protectionBoundary: $0.protectionBoundary
            )
        }

        let ride: TimetableRideState
        if let session = activeSession, session.isOpen {
            if session.isPaused {
                ride = .paused(sessionID: session.id)
            } else {
                ride = .running(
                    sessionID: session.id,
                    segmentStart: session.segmentStartedAt ?? session.startedAt
                )
            }
        } else if let open {
            ride = .arrived(sessionID: open.sessionID)
        } else {
            ride = .idle
        }

        let effect = TimetableGuardLogic.evaluate(
            ride: ride,
            blocks: blocks,
            openGuard: open,
            now: now
        )
        applyTimetableGuardEffect(effect, openGuard: openModel, now: now)
        suppressAwayIfTimetableQuiet(now: now)
        refreshEndBellIfDeadlineChanged(now: now)
        refreshTimetableHold(now: now)
    }

    func refreshCalendarBoard() async {
        if calendarBoard.authorizationStatus() == .notDetermined {
            _ = await calendarBoard.requestAccess()
        }
        await applyCalendarBoardFetch()
    }

    /// Hub では許可ダイアログを出さない。許可済みなら掲示を温めて案内板が読めるようにする。
    func refreshCalendarBoardIfAuthorized() async {
        guard calendarBoard.authorizationStatus() == .authorized else { return }
        await applyCalendarBoardFetch()
    }

    func currentUnadoptedNotice(at now: Date? = nil) -> CalendarOccurrence? {
        let now = now ?? clock.now
        return remainingUnadoptedNotices(at: now).first { occurrence in
            occurrence.startsAt <= now && now < occurrence.endsAt
        }
    }

    /// 起動中の回路。通過のままなら網は掛けない。
    func remainingUnadoptedNotices(at now: Date? = nil) -> [CalendarOccurrence] {
        unadoptedNotices(at: now ?? clock.now)
    }

    private func unadoptedNotices(at now: Date) -> [CalendarOccurrence] {
        let blocks = fetchActiveTimetableBlocks()
        return noticeOccurrences.filter { occurrence in
            occurrence.startsAt < occurrence.endsAt
                && now < occurrence.endsAt
                && !blocks.contains(where: {
                    $0.isActive && $0.calendarEventIdentifier == occurrence.eventIdentifier
                        && abs(($0.occurrenceStartKey ?? $0.startsAt.timeIntervalSince1970) - occurrence.occurrenceStartKey) < 0.5
                })
        }
    }

    private func unadoptedNoticeBlocks(at now: Date) -> [TimetableFitBlock] {
        unadoptedNotices(at: now).map {
            TimetableFitBlock(
                id: TimetableFit.noticeBlockID($0.id),
                title: $0.title,
                startsAt: $0.startsAt,
                endsAt: $0.endsAt
            )
        }
    }

    private func applyCalendarBoardFetch() async {
        let now = clock.now
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(172_800)
        let fetched: [CalendarOccurrence]
        do {
            fetched = try await calendarBoard.occurrences(from: start, to: end)
        } catch {
            return
        }
        // Membership sees every calendar so hiding a calendar does not 通過.
        let undo = persist(TimetableAdoption.refreshCalendarMembership(
            occurrences: fetched,
            membership: loadMembership(),
            membershipReconcileRange: start..<end
        ))
        noticeOccurrences = fetched.filter { occurrence in
            TimetableAdoption.isEligible(occurrence)
                && settings.isTimetableCalendarVisible(occurrence.calendarIdentifier)
        }
        guard saveBestEffort() else {
            undo.revert(in: modelContext)
            return
        }
        lastScheduledEndBellFireAt = nil
        reconcile(now: now)
    }

    func adoptOccurrence(_ occurrence: CalendarOccurrence, scope: TimetableAdoptionScope) {
        guard commitMembership(TimetableAdoption.adoptOccurrence(occurrence, scope: scope, membership: loadMembership())) else { return }
        lastScheduledEndBellFireAt = nil
        reconcile()
    }

    /// 案内板の掲示一行。今回だけ着発。発車は阻まない。
    func adoptCurrentNoticeThisTime() {
        guard let notice = currentUnadoptedNotice() else { return }
        adoptOccurrence(notice, scope: .occurrence)
    }

    func unadopt(blockID: UUID, scope: TimetableAdoptionScope) {
        guard commitMembership(TimetableAdoption.unadopt(blockID: blockID, scope: scope, membership: loadMembership())) else { return }
        lastScheduledEndBellFireAt = nil
        reconcile()
    }

    /// いま重なっているダイヤを今回だけ通過。確認は出さない。
    func unadoptCurrentOccurrence() {
        guard let current = timetableFit().currentBlock else { return }
        unadopt(blockID: current.id, scope: .occurrence)
    }

    func unadoptOccurrence(_ occurrence: CalendarOccurrence, scope: TimetableAdoptionScope) {
        guard commitMembership(TimetableAdoption.unadoptOccurrence(occurrence, scope: scope, membership: loadMembership())) else { return }
        lastScheduledEndBellFireAt = nil
        reconcile()
    }

    func adoptManualBlock(title: String, startsAt: Date, endsAt: Date) {
        guard commitMembership(
            TimetableAdoption.adoptManual(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? TimetableCopy.emptyManualTitle,
                startsAt: startsAt,
                endsAt: endsAt,
                membership: loadMembership()
            )
        ) else { return }
        lastScheduledEndBellFireAt = nil
        reconcile()
    }

    func handleTimetableNotification(identifier: String, action: String) {
        guard TimetableNotification.isTimetable(identifier) else { return }
        guard let parsed = TimetableNotification.parse(identifier) else { return }
        reconcile()
        guard ownsActiveRide else { return }
        guard activeSession?.id == parsed.sessionID else { return }
        let isPause = action == TimetableNotification.pauseAction
            || action == UNNotificationDefaultActionIdentifier
        if isPause {
            try? pause(timetableHeld: true)
        }
    }

    func clearTimetableQuietMessage() {
        presentation.clearTimetableQuietMessage()
    }

    func fetchActiveTimetableBlocks() -> [TimetableBlock] {
        fetchTimetableBlocks().filter(\.isActive)
    }

    func fetchTimetableBlocks() -> [TimetableBlock] {
        let descriptor = FetchDescriptor<TimetableBlock>(
            sortBy: [SortDescriptor(\.startsAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchTimetableBlocks(overlapping day: Date) -> [TimetableBlock] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return fetchActiveTimetableBlocks().filter { $0.startsAt < end && $0.endsAt > start }
    }

    func fetchSeriesRules() -> [TimetableSeriesRule] {
        let descriptor = FetchDescriptor<TimetableSeriesRule>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 今日の予定と、着発だけから計算した運転状況・ただいま・NEXT・LOAD。
    func openingTimetableBoard(
        now: Date? = nil,
        isTwentyFourHour: Bool = false,
        ticketsAboveCutoff: [ServiceLoadTicket] = []
    ) -> OpeningTimetableBoard {
        _ = openingTimetableRevision
        let now = now ?? clock.now
        return OpeningTimetableBoard.make(
            entries: openingTimetableEntries(on: now),
            now: now,
            isTwentyFourHour: isTwentyFourHour,
            referenceDay: now,
            ticketsAboveCutoff: ticketsAboveCutoff,
            calendar: calendar
        )
    }

    /// 予定に触れたとき。着発と通過を入れ替える。効くのは今回だけ。
    func toggleOpeningTimetableStop(_ entry: OpeningTimetableEntry) {
        switch entry.kind {
        case .stop(let blockID):
            unadopt(blockID: blockID, scope: .occurrence)
        case .passNotice(let occurrenceID):
            if let occurrence = noticeOccurrences.first(where: { $0.id == occurrenceID }) {
                adoptOccurrence(occurrence, scope: .occurrence)
            }
        case .passManual(let blockID):
            restoreManualStopToday(blockID: blockID)
        }
        openingTimetableRevision += 1
    }

    func openingTimetableEntries(on day: Date) -> [OpeningTimetableEntry] {
        let bounds = serviceDayBounds(for: day)
        var entries: [OpeningTimetableEntry] = []
        for block in fetchTimetableBlocks() where overlapsDay(block.startsAt, block.endsAt, bounds) && block.endsAt > block.startsAt {
            if block.isActive {
                entries.append(
                    OpeningTimetableEntry(
                        kind: .stop(blockID: block.id),
                        title: block.title,
                        startsAt: block.startsAt,
                        endsAt: block.endsAt
                    )
                )
            } else if block.source == .manual && block.isCancelled {
                entries.append(
                    OpeningTimetableEntry(
                        kind: .passManual(blockID: block.id),
                        title: block.title,
                        startsAt: block.startsAt,
                        endsAt: block.endsAt
                    )
                )
            }
        }

        let active = fetchActiveTimetableBlocks()
        for occurrence in noticeOccurrences where TimetableAdoption.isEligible(occurrence) && overlapsDay(occurrence.startsAt, occurrence.endsAt, bounds) {
            let adopted = active.contains { block in
                block.calendarEventIdentifier == occurrence.eventIdentifier
                    && abs((block.occurrenceStartKey ?? block.startsAt.timeIntervalSince1970) - occurrence.occurrenceStartKey) < 0.5
            }
            if adopted { continue }
            entries.append(
                OpeningTimetableEntry(
                    kind: .passNotice(occurrenceID: occurrence.id),
                    title: occurrence.title,
                    startsAt: occurrence.startsAt,
                    endsAt: occurrence.endsAt
                )
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
            return lhs.id < rhs.id
        }
    }

    private func restoreManualStopToday(blockID: UUID) {
        var membership = loadMembership()
        guard let index = membership.blocks.firstIndex(where: {
            $0.id == blockID && $0.source == .manual && $0.isCancelled
        }) else { return }
        membership.blocks[index].isCancelled = false
        guard commitMembership(membership) else { return }
        lastScheduledEndBellFireAt = nil
        reconcile()
    }

    private func serviceDayBounds(for day: Date) -> Range<Date> {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return start..<end
    }

    private func overlapsDay(_ startsAt: Date, _ endsAt: Date, _ day: Range<Date>) -> Bool {
        startsAt < day.upperBound && endsAt > day.lowerBound
    }

    private func fetchOpenTimetableGuard() -> TimetableGuard? {
        let descriptor = FetchDescriptor<TimetableGuard>(
            predicate: #Predicate { $0.resolvedAt == nil && $0.invalidatedAt == nil },
            sortBy: [SortDescriptor(\.notifiedAt, order: .reverse)]
        )
        let open = (try? modelContext.fetch(descriptor)) ?? []
        if let sessionID = activeSession?.id, let match = open.first(where: { $0.sessionID == sessionID }) {
            return match
        }
        return open.first
    }

    private func applyTimetableGuardEffect(
        _ effect: TimetableGuardEffect,
        openGuard: TimetableGuard?,
        now: Date
    ) {
        switch effect {
        case .none:
            return
        case .arm(let blockID, let notifiedAt, let protectionBoundary):
            let guardModel = TimetableGuard(
                sessionID: activeSession?.id ?? UUID(),
                blockID: blockID,
                notifiedAt: notifiedAt,
                protectionBoundary: protectionBoundary
            )
            modelContext.insert(guardModel)
            guard saveBestEffort() else {
                modelContext.delete(guardModel)
                return
            }
            scheduleTimetableNotification(
                guardID: guardModel.id,
                blockID: blockID,
                fireAt: notifiedAt
            )
        case .resolve:
            let previousResolved = openGuard?.resolvedAt
            openGuard?.resolvedAt = now
            guard saveBestEffort() else {
                openGuard?.resolvedAt = previousResolved
                return
            }
            cancelTimetableNotification(sessionID: openGuard?.sessionID ?? activeSession?.id)
        case .invalidate:
            let previousInvalidated = openGuard?.invalidatedAt
            openGuard?.invalidatedAt = now
            guard saveBestEffort() else {
                openGuard?.invalidatedAt = previousInvalidated
                return
            }
            cancelTimetableNotification(sessionID: openGuard?.sessionID ?? activeSession?.id)
        }
    }

    private func scheduleTimetableNotification(guardID: UUID, blockID: UUID, fireAt: Date) {
        guard let session = activeSession, ownsDeviceSideEffects(session) else { return }
        if isAlarmKitEndBellActive { return }
        let title = fetchActiveTimetableBlocks().first(where: { $0.id == blockID })?.title ?? TimetableCopy.board
        checkInNotifier.scheduleTimetablePause(
            sessionID: session.id,
            guardID: guardID,
            title: title,
            fireAt: fireAt
        )
    }

    private func cancelTimetableNotification(sessionID: UUID?) {
        guard let sessionID else { return }
        checkInNotifier.cancelTimetable(sessionID: sessionID)
    }

    private func refreshTimetableHold(now: Date) {
        guard timetableFit(at: now).currentOccupancy == nil else { return }
        var didChange = false
        if timetableQuietMessage != nil {
            timetableQuietMessage = nil
            didChange = true
        }
        for session in openPausedSessions() where session.timetableHeld {
            session.timetableHeld = false
            didChange = true
        }
        if didChange {
            bumpCompanionSync()
            _ = saveBestEffort()
        }
    }

    private func suppressAwayIfTimetableQuiet(now: Date) {
        guard timetableFit(at: now).shouldSuppressAway else { return }
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        if session.awayDueAt != nil || session.pendingCheckIn == .away {
            cancelAwayWatch(now: now)
        }
    }

    private func refreshEndBellIfDeadlineChanged(now: Date) {
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        refreshEndBell(for: session, now: now)
    }

    private func loadMembership() -> TimetableMembership {
        TimetableMembership(
            blocks: fetchTimetableBlocks().map { block in
                TimetableBlockRecord(
                    id: block.id,
                    title: block.title,
                    startsAt: block.startsAt,
                    endsAt: block.endsAt,
                    source: block.source,
                    adoptionScope: block.adoptionScope,
                    isCancelled: block.isCancelled,
                    needsReview: block.needsReview,
                    calendarEventIdentifier: block.calendarEventIdentifier,
                    calendarRecurrenceIdentifier: block.calendarRecurrenceIdentifier,
                    occurrenceStartKey: block.occurrenceStartKey
                )
            },
            rules: fetchSeriesRules().map { rule in
                TimetableSeriesRecord(
                    id: rule.id,
                    recurrenceIdentifier: rule.recurrenceIdentifier,
                    title: rule.title,
                    adopted: rule.adopted,
                    excludedOccurrenceStarts: rule.excludedOccurrenceStarts
                )
            }
        )
    }

    @discardableResult
    private func commitMembership(_ membership: TimetableMembership) -> Bool {
        let undo = persist(membership)
        guard saveBestEffort() else {
            undo.revert(in: modelContext)
            return false
        }
        return true
    }

    private func persist(_ membership: TimetableMembership) -> TimetablePersistUndo {
        var undo = TimetablePersistUndo()
        let existingBlocks = fetchTimetableBlocks()
        let blocksByID = Dictionary(uniqueKeysWithValues: existingBlocks.map { ($0.id, $0) })
        for record in membership.blocks {
            if let model = blocksByID[record.id] {
                undo.previousBlocks.append((model, TimetablePersistUndo.record(from: model)))
                TimetablePersistUndo.apply(record, to: model)
            } else {
                let model = TimetableBlock(
                    id: record.id,
                    title: record.title,
                    startsAt: record.startsAt,
                    endsAt: record.endsAt,
                    source: record.source,
                    adoptionScope: record.adoptionScope,
                    calendarEventIdentifier: record.calendarEventIdentifier,
                    calendarRecurrenceIdentifier: record.calendarRecurrenceIdentifier,
                    occurrenceStartKey: record.occurrenceStartKey
                )
                model.isCancelled = record.isCancelled
                model.needsReview = record.needsReview
                modelContext.insert(model)
                undo.insertedBlocks.append(model)
            }
        }

        let existingRules = fetchSeriesRules()
        let rulesByID = Dictionary(uniqueKeysWithValues: existingRules.map { ($0.id, $0) })
        for record in membership.rules {
            if let model = rulesByID[record.id] {
                undo.previousRules.append((model, TimetablePersistUndo.record(from: model)))
                TimetablePersistUndo.apply(record, to: model)
            } else {
                let model = TimetableSeriesRule(
                    id: record.id,
                    recurrenceIdentifier: record.recurrenceIdentifier,
                    title: record.title,
                    adopted: record.adopted
                )
                model.excludedOccurrenceStarts = record.excludedOccurrenceStarts
                modelContext.insert(model)
                undo.insertedRules.append(model)
            }
        }
        return undo
    }
}

/// Field snapshot for one `persist` call. A failed save reverts these models only.
private struct TimetablePersistUndo {
    var insertedBlocks: [TimetableBlock] = []
    var insertedRules: [TimetableSeriesRule] = []
    var previousBlocks: [(TimetableBlock, TimetableBlockRecord)] = []
    var previousRules: [(TimetableSeriesRule, TimetableSeriesRecord)] = []

    func revert(in context: ModelContext) {
        for block in insertedBlocks {
            context.delete(block)
        }
        for rule in insertedRules {
            context.delete(rule)
        }
        for (model, record) in previousBlocks {
            Self.apply(record, to: model)
        }
        for (model, record) in previousRules {
            Self.apply(record, to: model)
        }
    }

    static func record(from block: TimetableBlock) -> TimetableBlockRecord {
        TimetableBlockRecord(
            id: block.id,
            title: block.title,
            startsAt: block.startsAt,
            endsAt: block.endsAt,
            source: block.source,
            adoptionScope: block.adoptionScope,
            isCancelled: block.isCancelled,
            needsReview: block.needsReview,
            calendarEventIdentifier: block.calendarEventIdentifier,
            calendarRecurrenceIdentifier: block.calendarRecurrenceIdentifier,
            occurrenceStartKey: block.occurrenceStartKey
        )
    }

    static func record(from rule: TimetableSeriesRule) -> TimetableSeriesRecord {
        TimetableSeriesRecord(
            id: rule.id,
            recurrenceIdentifier: rule.recurrenceIdentifier,
            title: rule.title,
            adopted: rule.adopted,
            excludedOccurrenceStarts: rule.excludedOccurrenceStarts
        )
    }

    static func apply(_ record: TimetableBlockRecord, to model: TimetableBlock) {
        model.title = record.title
        model.startsAt = record.startsAt
        model.endsAt = record.endsAt
        model.source = record.source
        model.adoptionScope = record.adoptionScope
        model.isCancelled = record.isCancelled
        model.needsReview = record.needsReview
        model.calendarEventIdentifier = record.calendarEventIdentifier
        model.calendarRecurrenceIdentifier = record.calendarRecurrenceIdentifier
        model.occurrenceStartKey = record.occurrenceStartKey
    }

    static func apply(_ record: TimetableSeriesRecord, to model: TimetableSeriesRule) {
        model.recurrenceIdentifier = record.recurrenceIdentifier
        model.title = record.title
        model.adopted = record.adopted
        model.excludedOccurrenceStarts = record.excludedOccurrenceStarts
    }
}
