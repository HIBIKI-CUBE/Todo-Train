//
//  SessionManager+Timetable.swift
//  Todo train
//

import Foundation
import SwiftData
import UserNotifications

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
        persist(TimetableAdoption.refreshCalendarMembership(
            occurrences: fetched,
            membership: loadMembership()
        ))
        noticeOccurrences = fetched.filter { occurrence in
            TimetableAdoption.isEligible(occurrence)
                && settings.isTimetableCalendarVisible(occurrence.calendarIdentifier)
        }
        try? save()
        lastScheduledEndBellFireAt = nil
        reconcile(now: now)
    }

    func adoptOccurrence(_ occurrence: CalendarOccurrence, scope: TimetableAdoptionScope) {
        persist(TimetableAdoption.adoptOccurrence(occurrence, scope: scope, membership: loadMembership()))
        try? save()
        lastScheduledEndBellFireAt = nil
        reconcile()
    }

    /// 案内板の掲示一行。今回だけ着発。発車は阻まない。
    func adoptCurrentNoticeThisTime() {
        guard let notice = currentUnadoptedNotice() else { return }
        adoptOccurrence(notice, scope: .occurrence)
    }

    func unadopt(blockID: UUID, scope: TimetableAdoptionScope) {
        persist(TimetableAdoption.unadopt(blockID: blockID, scope: scope, membership: loadMembership()))
        try? save()
        lastScheduledEndBellFireAt = nil
        reconcile()
    }

    /// いま重なっているダイヤを今回だけ通過。確認は出さない。
    func unadoptCurrentOccurrence() {
        guard let current = timetableFit().currentBlock else { return }
        unadopt(blockID: current.id, scope: .occurrence)
    }

    func unadoptOccurrence(_ occurrence: CalendarOccurrence, scope: TimetableAdoptionScope) {
        persist(TimetableAdoption.unadoptOccurrence(occurrence, scope: scope, membership: loadMembership()))
        try? save()
        lastScheduledEndBellFireAt = nil
        reconcile()
    }

    func adoptManualBlock(title: String, startsAt: Date, endsAt: Date) {
        persist(
            TimetableAdoption.adoptManual(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? TimetableCopy.emptyManualTitle,
                startsAt: startsAt,
                endsAt: endsAt,
                membership: loadMembership()
            )
        )
        try? save()
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
        timetableQuietMessage = nil
    }

    func openTimetableProtectionBoundary(for sessionID: UUID) -> Date? {
        fetchOpenTimetableGuard().flatMap { guardModel in
            guardModel.sessionID == sessionID ? guardModel.protectionBoundary : nil
        }
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
            try? save()
            scheduleTimetableNotification(
                guardID: guardModel.id,
                blockID: blockID,
                fireAt: notifiedAt
            )
        case .pauseAt(let pauseAt):
            openGuard?.resolvedAt = now
            try? applyTimetableProtectionPause(at: pauseAt)
        case .resolve:
            openGuard?.resolvedAt = now
            cancelTimetableNotification(sessionID: openGuard?.sessionID ?? activeSession?.id)
            try? save()
        case .invalidate:
            openGuard?.invalidatedAt = now
            cancelTimetableNotification(sessionID: openGuard?.sessionID ?? activeSession?.id)
            try? save()
        }
    }

    private func applyTimetableProtectionPause(at pauseAt: Date) throws {
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        let clamped = max(pauseAt, session.segmentStartedAt ?? session.startedAt)
        flushToPaused(session, now: clamped)
        session.timetableHeld = true
        phase = .paused
        timetableQuietMessage = TimetableCopy.quiet
        noteCabinActivity(now: clamped, clearPendingIdle: true)
        bumpCompanionSync()
        if isAlarmKitEndBellActive {
            alarmScheduler.pause(sessionID: session.id)
        } else {
            alarmScheduler.cancel(sessionID: session.id)
        }
        cancelTimetableNotification(sessionID: session.id)
        try save()
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
            try? save()
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

    private func persist(_ membership: TimetableMembership) {
        let existingBlocks = fetchTimetableBlocks()
        let blocksByID = Dictionary(uniqueKeysWithValues: existingBlocks.map { ($0.id, $0) })
        for record in membership.blocks {
            if let model = blocksByID[record.id] {
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
            }
        }

        let existingRules = fetchSeriesRules()
        let rulesByID = Dictionary(uniqueKeysWithValues: existingRules.map { ($0.id, $0) })
        for record in membership.rules {
            if let model = rulesByID[record.id] {
                model.recurrenceIdentifier = record.recurrenceIdentifier
                model.title = record.title
                model.adopted = record.adopted
                model.excludedOccurrenceStarts = record.excludedOccurrenceStarts
            } else {
                let model = TimetableSeriesRule(
                    id: record.id,
                    recurrenceIdentifier: record.recurrenceIdentifier,
                    title: record.title,
                    adopted: record.adopted
                )
                model.excludedOccurrenceStarts = record.excludedOccurrenceStarts
                modelContext.insert(model)
            }
        }
    }
}
