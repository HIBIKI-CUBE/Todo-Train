//
//  SessionManager.swift
//  Todo train
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class SessionManager {
    private(set) var phase: SessionPhase = .idle
    private(set) var activeServiceDay: ServiceDay?
    private(set) var activeSession: WorkSession?
    private(set) var needsServiceDayEndPrompt = false

    private let modelContext: ModelContext
    private let clock: any SessionClock
    private let calendar: Calendar
    private let pauseLimit: Int

    init(
        modelContext: ModelContext,
        clock: any SessionClock = SystemSessionClock(),
        calendar: Calendar = .current,
        pauseLimit: Int = PauseLimitGuard.defaultLimit
    ) {
        self.modelContext = modelContext
        self.clock = clock
        self.calendar = calendar
        self.pauseLimit = pauseLimit
    }

    var elapsedSeconds: TimeInterval {
        guard let activeSession else { return 0 }
        return activeSession.elapsedSeconds(at: clock.now)
    }

    var remainingSeconds: TimeInterval {
        guard let activeSession else { return 0 }
        return activeSession.remainingSeconds(at: clock.now)
    }

    var pausedTicketCount: Int {
        openPausedSessions().count
    }

    var isInService: Bool {
        guard let activeServiceDay, activeServiceDay.isOpen else { return false }
        return activeServiceDay.calendarDayKey == ServiceDay.dayKey(for: clock.now, calendar: calendar)
    }

    // MARK: - Service day

    func startService(now: Date? = nil) throws {
        let now = now ?? clock.now
        let todayKey = ServiceDay.dayKey(for: now, calendar: calendar)

        if let open = fetchOpenServiceDay() {
            if open.calendarDayKey != todayKey {
                activeServiceDay = open
                needsServiceDayEndPrompt = true
                throw SessionError.serviceDayNeedsEnd
            }
            activeServiceDay = open
            throw SessionError.serviceAlreadyActive
        }

        let day = ServiceDay(startedAt: now, calendarDayKey: todayKey)
        modelContext.insert(day)
        activeServiceDay = day
        needsServiceDayEndPrompt = false
        try save()
        reconcile(now: now)
    }

    func endService(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let day = activeServiceDay ?? fetchOpenServiceDay(), day.isOpen else {
            throw SessionError.noActiveService
        }

        if let session = activeSession, session.isOpen, !session.isPaused {
            throw SessionError.cannotEndServiceWhileRunning
        }
        if let running = fetchRunningSession() {
            activeSession = running
            throw SessionError.cannotEndServiceWhileRunning
        }

        day.endedAt = now
        activeServiceDay = nil
        needsServiceDayEndPrompt = false
        // Paused open sessions remain for transfer UI in a later sprint.
        if activeSession?.isPaused == true {
            activeSession = nil
            phase = .idle
        }
        try save()
        reconcile(now: now)
    }

    // MARK: - Boarding

    func board(ticket: Ticket, now: Date? = nil) throws {
        let now = now ?? clock.now
        try ensureServiceAllowsBoarding(at: now)

        guard ticket.isOpen else {
            throw SessionError.ticketAlreadyClosed
        }

        if let running = fetchRunningSession() {
            activeSession = running
            reconcile(now: now)
            throw SessionError.alreadyBoarding
        }

        if let paused = openPausedSessions().first(where: { $0.ticket?.id == ticket.id }) {
            activeSession = paused
            try resume(now: now)
            return
        }

        let estimate = min(max(ticket.estimatedSeconds, 1), Ticket.maxEstimatedSeconds)
        let session = WorkSession(
            startedAt: now,
            estimatedSecondsAtStart: estimate,
            ticket: ticket
        )
        modelContext.insert(session)
        activeSession = session
        phase = .running
        try save()
        reconcile(now: now)
    }

    func pause(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard !session.isPaused else {
            phase = .paused
            return
        }

        let pausedCount = pausedTicketCount
        guard PauseLimitGuard.canPause(currentPausedCount: pausedCount, limit: pauseLimit) else {
            throw SessionError.pauseLimitReached
        }

        if let segmentStartedAt = session.segmentStartedAt {
            session.accumulatedActiveSeconds += now.timeIntervalSince(segmentStartedAt)
        }
        session.segmentStartedAt = nil
        session.pausedAt = now
        phase = .paused
        try save()
        reconcile(now: now)
    }

    func resume(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard session.isPaused else {
            throw SessionError.notPaused
        }

        session.pausedAt = nil
        session.segmentStartedAt = now
        phase = .running
        try save()
        reconcile(now: now)
    }

    func extend(by seconds: TimeInterval, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard !session.isPaused else {
            throw SessionError.notRunning
        }
        guard seconds > 0 else { return }

        session.budgetSecondsAtStart += Int(seconds.rounded())
        try save()
        reconcile(now: now)
    }

    func arrive(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }

        if !session.isPaused, let segmentStartedAt = session.segmentStartedAt {
            session.accumulatedActiveSeconds += now.timeIntervalSince(segmentStartedAt)
            session.segmentStartedAt = nil
        }
        session.pausedAt = nil
        session.endedAt = now
        session.outcome = .arrived

        if let ticket = session.ticket {
            ticket.closedAt = now
            ticket.closureKind = .arrived
        }

        activeSession = nil
        phase = .idle
        try save()
        reconcile(now: now)
    }

    // MARK: - Lifecycle

    func reconcile(now: Date? = nil) {
        let now = now ?? clock.now

        if let day = activeServiceDay ?? fetchOpenServiceDay() {
            activeServiceDay = day
            let todayKey = ServiceDay.dayKey(for: now, calendar: calendar)
            needsServiceDayEndPrompt = day.isOpen && day.calendarDayKey != todayKey
        } else {
            activeServiceDay = nil
            needsServiceDayEndPrompt = false
        }

        guard let session = activeSession, session.isOpen else {
            if let running = fetchRunningSession() {
                activeSession = running
            } else {
                phase = .idle
                return
            }
            return reconcile(now: now)
        }

        if session.isPaused {
            phase = .paused
            return
        }

        if session.remainingSeconds(at: now) <= 0 {
            phase = .overtime
        } else {
            phase = .running
        }
    }

    func recoverOnLaunch() throws {
        let now = clock.now
        let todayKey = ServiceDay.dayKey(for: now, calendar: calendar)

        if let openDay = fetchOpenServiceDay() {
            activeServiceDay = openDay
            needsServiceDayEndPrompt = openDay.calendarDayKey != todayKey
        } else {
            activeServiceDay = nil
            needsServiceDayEndPrompt = false
        }

        let openSessions = fetchOpenSessions()
        if openSessions.count > 1 {
            let sorted = openSessions.sorted { $0.startedAt > $1.startedAt }
            for stale in sorted.dropFirst() {
                if !stale.isPaused, let segmentStartedAt = stale.segmentStartedAt {
                    stale.accumulatedActiveSeconds += now.timeIntervalSince(segmentStartedAt)
                    stale.segmentStartedAt = nil
                }
                stale.pausedAt = nil
                stale.endedAt = now
                stale.outcome = .recoveryConflict
            }
        }

        let remainingOpen = fetchOpenSessions().sorted { $0.startedAt > $1.startedAt }
        if let running = remainingOpen.first(where: { !$0.isPaused }) {
            activeSession = running
        } else if let paused = remainingOpen.first {
            activeSession = paused
        } else {
            activeSession = nil
        }

        try save()
        reconcile(now: now)
    }

    // MARK: - Queries

    private func ensureServiceAllowsBoarding(at now: Date) throws {
        let todayKey = ServiceDay.dayKey(for: now, calendar: calendar)

        guard let day = activeServiceDay ?? fetchOpenServiceDay(), day.isOpen else {
            throw SessionError.noActiveService
        }
        activeServiceDay = day

        if day.calendarDayKey != todayKey {
            needsServiceDayEndPrompt = true
            throw SessionError.serviceDayNeedsEnd
        }
    }

    private func fetchOpenServiceDay() -> ServiceDay? {
        let descriptor = FetchDescriptor<ServiceDay>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchOpenSessions() -> [WorkSession] {
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchRunningSession() -> WorkSession? {
        fetchOpenSessions().first { !$0.isPaused }
    }

    private func openPausedSessions() -> [WorkSession] {
        fetchOpenSessions().filter(\.isPaused)
    }

    private func save() throws {
        try modelContext.save()
    }
}
