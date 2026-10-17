//
//  SessionManager+Queries.swift
//  Todo train
//

import Foundation
import Observation
import SwiftData
import TodoTrainSync
#if canImport(UIKit)
import UIKit
#endif

extension SessionManager {
    /// Refresh the open service day and the end-of-day flag without throwing.
    /// `boardingEligibility` reads those flags, so they have to match the
    /// store before the gate is consulted.
    func syncServiceDayForBoarding(at now: Date) {
        let todayKey = ServiceDay.dayKey(for: now, calendar: calendar)
        guard let day = activeServiceDay ?? fetchOpenServiceDay(), day.isOpen else {
            needsServiceDayEndPrompt = false
            return
        }
        activeServiceDay = day
        needsServiceDayEndPrompt = day.calendarDayKey != todayKey
    }

    func ensureServiceAllowsBoarding(at now: Date) throws {
        syncServiceDayForBoarding(at: now)
        if needsServiceDayEndPrompt {
            throw SessionError.serviceDayNeedsEnd
        }
        guard isInService else {
            throw SessionError.noActiveService
        }
    }

    func fetchOpenServiceDay() -> ServiceDay? {
        fetchOpenServiceDays().first
    }

    func fetchOpenServiceDays() -> [ServiceDay] {
        let descriptor = FetchDescriptor<ServiceDay>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchOpenSessions() -> [WorkSession] {
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchRunningSession() -> WorkSession? {
        fetchOpenSessions().first { !$0.isPaused }
    }

    func openPausedSessions() -> [WorkSession] {
        fetchOpenSessions().filter(\.isPaused)
    }

    func enqueueArrivalMomentIfNeeded(_ session: WorkSession) {
        guard Punctuality.shouldCelebrateArrival(outcome: session.outcome) else { return }
        let title = session.ticket?.title ?? "切符"
        enqueuePunctualityMoment(
            PunctualityMoment(
                kind: .arrival(
                    title: title,
                    estimateSeconds: Punctuality.judgedEstimateSeconds(for: session),
                    actualSeconds: session.accumulatedActiveSeconds,
                    punctuality: Punctuality.classify(session)
                ),
                arrivedSessionID: session.id
            )
        )
    }

    func enqueuePunctualityMoment(_ moment: PunctualityMoment) {
        presentation.enqueuePunctualityMoment(moment)
    }

    /// Arrivals closed during this service window (startedAt ... endedBy).
    func arrivedSessions(inServiceDay day: ServiceDay, endedBy end: Date) -> [WorkSession] {
        let start = day.startedAt
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate<WorkSession> { session in
                session.endedAt != nil
            }
        )
        let ended = (try? modelContext.fetch(descriptor)) ?? []
        return ended.filter { session in
            guard session.outcome == .arrived, let endedAt = session.endedAt else { return false }
            return endedAt >= start && endedAt <= end
        }
    }

    func save() throws {
        if let saveErrorForTesting {
            throw saveErrorForTesting
        }
        try modelContext.save()
    }

    /// Non-throwing lifecycle paths use this instead of swallowing `save()` with `try?`.
    /// Logs and returns false so callers can skip follow-on side effects that assume durability.
    @discardableResult
    func saveBestEffort(_ operation: StaticString = #function) -> Bool {
        do {
            try save()
            return true
        } catch {
            SessionPersistenceLog.saveFailed(operation: operation, error: error)
            return false
        }
    }

    func workSessions(onDayKey dayKey: String) -> [WorkSession] {
        guard let day = HistoryStats.date(from: dayKey, calendar: calendar) else { return [] }
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let descriptor = FetchDescriptor<WorkSession>(
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { session in
            let ended = session.endedAt ?? clock.now
            return session.startedAt < end && ended > start
        }
    }

    func historyStrips(onDayKey dayKey: String) -> [DayClockStrip] {
        guard let day = HistoryStats.date(from: dayKey, calendar: calendar) else { return [] }
        return fetchTimetableBlocks(overlapping: day).map { block in
            DayClockStrip(
                id: block.id,
                title: block.title,
                startsAt: block.startsAt,
                endsAt: block.endsAt,
                style: .history
            )
        }
    }

    func setExtensionReason(_ reason: String?, on item: SessionExtension) {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        item.reason = trimmed.isEmpty ? nil : trimmed
        _ = saveBestEffort()
    }
}
