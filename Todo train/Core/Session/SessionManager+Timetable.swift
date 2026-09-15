//
//  SessionManager+Timetable.swift
//  Todo train
//

import Foundation
import SwiftData

extension SessionManager {
    func fitBlocks(from blocks: [TimetableBlock]? = nil) -> [TimetableFit.Block] {
        let records = blocks ?? fetchTimetableBlocks()
        return records.map {
            TimetableFit.Block(
                id: $0.id,
                title: $0.title,
                startsAt: $0.startsAt,
                endsAt: $0.endsAt,
                isCancelled: $0.isCancelled
            )
        }
    }

    func timetablePauseAt(now: Date? = nil) -> Date? {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen, !session.isPaused else { return nil }
        let ride = TimetableGuardLogic.Ride(
            sessionID: session.id,
            startedAt: session.startedAt,
            segmentStartedAt: session.segmentStartedAt,
            isOpen: session.isOpen,
            isPaused: session.isPaused,
            endedAt: session.endedAt
        )
        if let overlapping = TimetableGuardLogic.overlappingEligibleBlock(
            ride: ride,
            blocks: fitBlocks(),
            now: now
        ) {
            return TimetableFit.protectionBoundary(forStart: overlapping.startsAt)
        }
        if let upcoming = TimetableGuardLogic.upcomingEligibleBlock(
            ride: ride,
            blocks: fitBlocks(),
            now: now
        ) {
            return TimetableFit.protectionBoundary(forStart: upcoming.startsAt)
        }
        return nil
    }

    func nextTimetableBlock(now: Date? = nil) -> TimetableBlock? {
        let now = now ?? clock.now
        return fetchTimetableBlocks()
            .filter { $0.isActive && $0.endsAt > now }
            .sorted { $0.startsAt < $1.startsAt }
            .first
    }

    func applyTimetableEffects(now: Date) {
        let blocks = fitBlocks()
        let guards = fetchTimetableGuards()
        let ride = activeSession.map {
            TimetableGuardLogic.Ride(
                sessionID: $0.id,
                startedAt: $0.startedAt,
                segmentStartedAt: $0.segmentStartedAt,
                isOpen: $0.isOpen,
                isPaused: $0.isPaused,
                endedAt: $0.endedAt
            )
        }
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: blocks,
            guards: guards.map {
                TimetableGuardLogic.StoredGuard(
                    id: $0.id,
                    sessionID: $0.sessionID,
                    blockID: $0.blockID,
                    notifiedAt: $0.notifiedAt,
                    protectionBoundary: $0.protectionBoundary,
                    resolvedAt: $0.resolvedAt,
                    invalidatedAt: $0.invalidatedAt
                )
            },
            now: now
        )
        var didPause = false
        for effect in effects {
            applyTimetableEffect(effect, now: now, didPause: &didPause)
        }
        scheduleUpcomingTimetableNotice(now: now)
    }

    func refreshCalendarBoard() async {
        let auth = await calendarBoard.requestAccess()
        guard auth == .authorized else {
            noticeOccurrences = []
            return
        }
        let now = clock.now
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let found = await calendarBoard.occurrences(from: start, to: end)
        noticeOccurrences = found.filter(\.isAdoptable)
        try? refreshCalendarMembership(occurrences: found)
    }

    func adoptManualBlock(title: String, startsAt: Date, endsAt: Date) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = TimetableBlock(
            title: trimmed.isEmpty ? "枠" : trimmed,
            startsAt: startsAt,
            endsAt: max(endsAt, startsAt.addingTimeInterval(60)),
            source: .manual
        )
        modelContext.insert(block)
        try save()
        bumpCompanionSync()
        reconcile()
        refreshEndBellIfRunning()
    }

    func adoptOccurrence(_ occurrence: CalendarOccurrence, scope: TimetableAdoptionScope) throws {
        guard occurrence.isAdoptable else { return }
        if scope == .series, let recurrence = occurrence.recurrenceIdentifier, !recurrence.isEmpty {
            upsertSeriesRule(recurrenceIdentifier: recurrence, title: occurrence.title, adopted: true)
            var rule = fetchSeriesRule(recurrenceIdentifier: recurrence)
            rule?.excludedOccurrenceStarts.removeAll {
                abs($0.timeIntervalSince(occurrence.startsAt)) < 1
            }
        }
        if let existing = blockMatching(occurrence: occurrence) {
            existing.title = occurrence.title
            existing.startsAt = occurrence.startsAt
            existing.endsAt = occurrence.endsAt
            existing.isCancelled = false
            existing.needsReview = false
            existing.adoptionScope = scope
            existing.calendarEventIdentifier = occurrence.eventIdentifier
            existing.calendarRecurrenceIdentifier = occurrence.recurrenceIdentifier
            existing.occurrenceStartKey = occurrence.startsAt
        } else {
            let block = TimetableBlock(
                title: occurrence.title,
                startsAt: occurrence.startsAt,
                endsAt: occurrence.endsAt,
                source: .calendar,
                adoptionScope: scope,
                calendarEventIdentifier: occurrence.eventIdentifier,
                calendarRecurrenceIdentifier: occurrence.recurrenceIdentifier,
                occurrenceStartKey: occurrence.startsAt
            )
            modelContext.insert(block)
        }
        try save()
        bumpCompanionSync()
        reconcile()
        refreshEndBellIfRunning()
    }

    func unadopt(block: TimetableBlock, seriesToo: Bool) throws {
        if seriesToo, let recurrence = block.calendarRecurrenceIdentifier, !recurrence.isEmpty {
            upsertSeriesRule(recurrenceIdentifier: recurrence, title: block.title, adopted: false)
            for item in fetchTimetableBlocks() where item.calendarRecurrenceIdentifier == recurrence {
                item.isCancelled = true
            }
        } else if block.adoptionScope == .series, let recurrence = block.calendarRecurrenceIdentifier {
            if let rule = fetchSeriesRule(recurrenceIdentifier: recurrence), rule.adopted {
                if !rule.excludedOccurrenceStarts.contains(where: {
                    abs($0.timeIntervalSince(block.startsAt)) < 1
                }) {
                    rule.excludedOccurrenceStarts.append(block.startsAt)
                }
            }
            block.isCancelled = true
        } else {
            block.isCancelled = true
        }
        try save()
        bumpCompanionSync()
        reconcile()
        refreshEndBellIfRunning()
    }

    func refreshCalendarMembership(occurrences: [CalendarOccurrence]) throws {
        let rules = fetchSeriesRules().map {
            TimetableAdoption.Rule(
                recurrenceIdentifier: $0.recurrenceIdentifier,
                adopted: $0.adopted,
                excludedOccurrenceStarts: $0.excludedOccurrenceStarts
            )
        }
        let existing = fetchTimetableBlocks().map {
            TimetableAdoption.ExistingBlock(
                id: $0.id,
                calendarEventIdentifier: $0.calendarEventIdentifier,
                calendarRecurrenceIdentifier: $0.calendarRecurrenceIdentifier,
                occurrenceStartKey: $0.occurrenceStartKey,
                source: $0.source,
                isCancelled: $0.isCancelled
            )
        }
        let decisions = TimetableAdoption.materialize(
            occurrences: occurrences,
            rules: rules,
            existing: existing
        )
        let byID = Dictionary(uniqueKeysWithValues: fetchTimetableBlocks().map { ($0.id, $0) })
        for decision in decisions {
            switch decision {
            case .keep:
                continue
            case .insert(let occurrence, let scope):
                let block = TimetableBlock(
                    title: occurrence.title,
                    startsAt: occurrence.startsAt,
                    endsAt: occurrence.endsAt,
                    source: .calendar,
                    adoptionScope: scope,
                    calendarEventIdentifier: occurrence.eventIdentifier,
                    calendarRecurrenceIdentifier: occurrence.recurrenceIdentifier,
                    occurrenceStartKey: occurrence.startsAt
                )
                modelContext.insert(block)
            case .update(let blockID, let occurrence):
                guard let block = byID[blockID] else { continue }
                block.title = occurrence.title
                block.startsAt = occurrence.startsAt
                block.endsAt = occurrence.endsAt
                block.isCancelled = false
                block.needsReview = false
                block.calendarEventIdentifier = occurrence.eventIdentifier
                block.calendarRecurrenceIdentifier = occurrence.recurrenceIdentifier
                block.occurrenceStartKey = occurrence.startsAt
            case .cancel(let blockID):
                byID[blockID]?.isCancelled = true
            }
        }
        try save()
        reconcile()
        refreshEndBellIfRunning()
    }

    func nextNoticeFireAt(now: Date, session: WorkSession) -> (block: TimetableFit.Block, fireAt: Date)? {
        let ride = TimetableGuardLogic.Ride(
            sessionID: session.id,
            startedAt: session.startedAt,
            segmentStartedAt: session.segmentStartedAt,
            isOpen: session.isOpen,
            isPaused: session.isPaused,
            endedAt: session.endedAt
        )
        if let overlapping = TimetableGuardLogic.overlappingEligibleBlock(
            ride: ride,
            blocks: fitBlocks(),
            now: now
        ) {
            let boundary = TimetableFit.protectionBoundary(forStart: overlapping.startsAt)
            guard now < boundary else { return nil }
            return (overlapping, overlapping.startsAt)
        }
        guard let upcoming = TimetableGuardLogic.upcomingEligibleBlock(
            ride: ride,
            blocks: fitBlocks(),
            now: now
        ) else { return nil }
        return (upcoming, upcoming.startsAt)
    }

    private func applyTimetableEffect(_ effect: TimetableGuardLogic.Effect, now: Date, didPause: inout Bool) {
        switch effect {
        case .none:
            return
        case .arm(let blockID, let notifiedAt, let protectionBoundary):
            guard let session = activeSession else { return }
            let record = TimetableGuard(
                sessionID: session.id,
                blockID: blockID,
                notifiedAt: notifiedAt,
                protectionBoundary: protectionBoundary
            )
            modelContext.insert(record)
            try? save()
        case .pause(let at, let guardID, _):
            guard !didPause, let session = activeSession, session.isOpen, !session.isPaused else { return }
            didPause = true
            flushToPaused(session, now: at)
            phase = .paused
            if let guardID, let record = fetchTimetableGuards().first(where: { $0.id == guardID }) {
                record.resolvedAt = now
            } else if let sessionID = activeSession?.id {
                for record in fetchTimetableGuards() where record.sessionID == sessionID && record.isOpen {
                    record.resolvedAt = now
                }
            }
            timetableQuietMessage = TimetableCopy.pausedQuietly
            noteCabinActivity(now: now, clearPendingIdle: true)
            bumpCompanionSync()
            try? save()
            checkInNotifier.cancel(sessionID: session.id)
            if isAlarmKitEndBellActive {
                alarmScheduler.pause(sessionID: session.id)
            } else {
                alarmScheduler.cancel(sessionID: session.id)
            }
        case .resolve(let guardID):
            fetchTimetableGuards().first { $0.id == guardID }?.resolvedAt = now
            try? save()
        case .invalidate(let guardID):
            fetchTimetableGuards().first { $0.id == guardID }?.invalidatedAt = now
            try? save()
        }
    }

    private func scheduleUpcomingTimetableNotice(now: Date) {
        guard let session = activeSession, session.isOpen, !session.isPaused else {
            if let session = activeSession {
                checkInNotifier.cancelTimetablePause(sessionID: session.id)
            }
            return
        }
        guard ownsDeviceSideEffects(session) else { return }
        if isAlarmKitEndBellActive {
            checkInNotifier.cancelTimetablePause(sessionID: session.id)
            return
        }
        guard let upcoming = nextNoticeFireAt(now: now, session: session) else {
            checkInNotifier.cancelTimetablePause(sessionID: session.id)
            return
        }
        checkInNotifier.scheduleTimetablePause(
            sessionID: session.id,
            guardID: session.id,
            title: upcoming.block.title,
            fireAt: upcoming.fireAt
        )
    }

    private func refreshEndBellIfRunning() {
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        refreshEndBell(for: session, now: clock.now)
    }

    func fetchTimetableBlocks() -> [TimetableBlock] {
        let descriptor = FetchDescriptor<TimetableBlock>(sortBy: [SortDescriptor(\.startsAt)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchTimetableGuards() -> [TimetableGuard] {
        let descriptor = FetchDescriptor<TimetableGuard>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchSeriesRules() -> [TimetableSeriesRule] {
        let descriptor = FetchDescriptor<TimetableSeriesRule>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchSeriesRule(recurrenceIdentifier: String) -> TimetableSeriesRule? {
        fetchSeriesRules().first { $0.recurrenceIdentifier == recurrenceIdentifier }
    }

    private func upsertSeriesRule(recurrenceIdentifier: String, title: String, adopted: Bool) {
        if let existing = fetchSeriesRule(recurrenceIdentifier: recurrenceIdentifier) {
            existing.adopted = adopted
            existing.title = title
            if adopted {
                existing.excludedOccurrenceStarts = []
            }
            return
        }
        modelContext.insert(
            TimetableSeriesRule(
                recurrenceIdentifier: recurrenceIdentifier,
                title: title,
                adopted: adopted
            )
        )
    }

    private func blockMatching(occurrence: CalendarOccurrence) -> TimetableBlock? {
        fetchTimetableBlocks().first { block in
            block.calendarEventIdentifier == occurrence.eventIdentifier
                && (
                    block.occurrenceStartKey.map { abs($0.timeIntervalSince(occurrence.startsAt)) < 1 }
                        ?? true
                )
        }
    }
}
