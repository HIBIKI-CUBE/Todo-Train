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
    private let settings: AppSettings
    private let overtimeNotifier: any OvertimeNotifying
    private let overrideCounter: any OverrideCounting
    private let liveActivityManager: any LiveActivityManaging
    private let alarmScheduler: any AlarmScheduling

    /// Today's temporary-pause override count (for UI).
    private(set) var todayOverrideCount: Int = 0

    /// Session IDs whose end bell was dismissed by the user (StandBy cancel).
    /// Prevents recover / foreground from silently re-scheduling the same bell.
    private var suppressedEndBellSessionIDs: Set<UUID> = []

    /// Ephemeral moments. Not persisted, not a score.
    /// Arrival haptic is owned by `ArrivalInvalidateOverlay`; enqueue ticks only for 定時運行.
    private(set) var punctualityQueue: [PunctualityMoment] = []
    /// Bumps when a 定時運行 moment is enqueued (haptic). Consume must not tick.
    private(set) var punctualityHapticTick: Int = 0

    var punctualityMoment: PunctualityMoment? { punctualityQueue.first }

    var pauseLimit: Int { settings.pauseLimit }

    /// True when Settings end-bell is on and AlarmKit is authorized (owns LA + alert).
    var isAlarmKitEndBellActive: Bool {
        EndBellDelivery.channel(
            endBellEnabled: settings.endBellEnabled,
            alarmKitAuthorized: alarmScheduler.isAuthorized
        ) == .alarmKit
    }

    init(
        modelContext: ModelContext,
        clock: any SessionClock = SystemSessionClock(),
        calendar: Calendar = .current,
        settings: AppSettings = .shared,
        overtimeNotifier: (any OvertimeNotifying)? = nil,
        overrideCounter: (any OverrideCounting)? = nil,
        liveActivityManager: (any LiveActivityManaging)? = nil,
        alarmScheduler: (any AlarmScheduling)? = nil
    ) {
        self.modelContext = modelContext
        self.clock = clock
        self.calendar = calendar
        self.settings = settings
        self.overtimeNotifier = overtimeNotifier ?? NoOpOvertimeNotifier()
        self.overrideCounter = overrideCounter ?? OverrideCounter.shared
        self.liveActivityManager = liveActivityManager ?? NoOpLiveActivityManager()
        self.alarmScheduler = alarmScheduler ?? NoOpAlarmScheduler()
        self.todayOverrideCount = self.overrideCounter.count(
            forDayKey: ServiceDay.dayKey(for: clock.now, calendar: calendar)
        )
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
        pausedSessions.count
    }

    /// Open sessions that are currently paused (for Hub resume UI).
    var pausedSessions: [WorkSession] {
        openPausedSessions()
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
        overtimeNotifier.requestAuthorizationIfNeeded()
        alarmScheduler.requestAuthorizationIfNeeded()
        refreshTodayOverrideCount(at: now)
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
        // Spec S-04: paused tickets must be resolved (途中下車→乗り継ぎ or 放棄). No silent carry-over.
        if !openPausedSessions().isEmpty {
            throw SessionError.unresolvedPausedTickets
        }

        let arrivedToday = arrivedSessions(inServiceDay: day, endedBy: now)
        let onTimeService = Punctuality.isOnTimeService(arrivedSessions: arrivedToday)

        day.endedAt = now
        activeServiceDay = nil
        needsServiceDayEndPrompt = false
        if activeSession?.isPaused == true {
            activeSession = nil
            phase = .idle
        }
        overtimeNotifier.cancelAll()
        alarmScheduler.cancelAll()
        try save()
        reconcile(now: now)
        if onTimeService {
            enqueuePunctualityMoment(PunctualityMoment(kind: .onTimeService))
        }
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
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        refreshEndBell(for: session, now: now)
    }

    /// Pause the current ride in the store, then board `ticket`, without publishing `.paused`.
    /// Focus stays up (`ContentView` only covers `.running` / `.overtime`).
    func switchBoard(ticket: Ticket, now: Date? = nil) throws {
        let now = now ?? clock.now
        try ensureServiceAllowsBoarding(at: now)

        guard ticket.isOpen else {
            throw SessionError.ticketAlreadyClosed
        }

        if let running = fetchRunningSession() {
            if running.ticket?.id == ticket.id {
                activeSession = running
                reconcile(now: now)
                return
            }

            guard PauseLimitGuard.canPause(
                currentPausedCount: pausedTicketCount,
                limit: settings.pauseLimit
            ) else {
                throw SessionError.pauseLimitReached
            }

            try parkRunningSessionForSwitch(running, now: now)
        }

        try board(ticket: ticket, now: now)
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
        guard PauseLimitGuard.canPause(currentPausedCount: pausedCount, limit: settings.pauseLimit) else {
            throw SessionError.pauseLimitReached
        }

        try applyPause(session: session, now: now)
    }

    /// Bypass pause limit (臨時停車). Increments today's override count. No hard cap.
    @discardableResult
    func forcePause(now: Date? = nil) throws -> Int {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard !session.isPaused else {
            phase = .paused
            return todayOverrideCount
        }

        try applyPause(session: session, now: now)
        let dayKey = ServiceDay.dayKey(for: now, calendar: calendar)
        todayOverrideCount = overrideCounter.increment(forDayKey: dayKey)
        return todayOverrideCount
    }

    private func applyPause(session: WorkSession, now: Date, syncAlarm: Bool = true) throws {
        if let segmentStartedAt = session.segmentStartedAt {
            session.accumulatedActiveSeconds += now.timeIntervalSince(segmentStartedAt)
        }
        session.segmentStartedAt = nil
        session.pausedAt = now
        phase = .paused
        overtimeNotifier.cancel(sessionID: session.id)
        liveActivityManager.end()
        // Always cancel (never pause) so AlarmKit Live Activities do not linger while paused.
        if syncAlarm {
            alarmScheduler.cancel(sessionID: session.id)
        }
        try save()
        reconcile(now: now)
    }

    /// Park the running session without setting `phase` to `.paused` (no Focus cover tear-down).
    private func parkRunningSessionForSwitch(_ session: WorkSession, now: Date) throws {
        if let segmentStartedAt = session.segmentStartedAt {
            session.accumulatedActiveSeconds += now.timeIntervalSince(segmentStartedAt)
        }
        session.segmentStartedAt = nil
        session.pausedAt = now
        overtimeNotifier.cancel(sessionID: session.id)
        liveActivityManager.end()
        alarmScheduler.cancel(sessionID: session.id)
        try save()
    }

    /// StandBy / system AlarmKit pause → mirror into the open session (no AlarmKit echo).
    /// When pause limit is full, records a temporary pause (臨時停車) so Alarm and DB stay aligned.
    /// Caller (AlarmKitScheduler) must cancel the alarm after this so the paused LA disappears.
    func pauseFromAlarmKit(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        let pausedCount = pausedTicketCount
        if PauseLimitGuard.canPause(currentPausedCount: pausedCount, limit: settings.pauseLimit) {
            try applyPause(session: session, now: now, syncAlarm: false)
        } else {
            try applyPause(session: session, now: now, syncAlarm: false)
            let dayKey = ServiceDay.dayKey(for: now, calendar: calendar)
            todayOverrideCount = overrideCounter.increment(forDayKey: dayKey)
        }
    }

    /// StandBy dismiss / cancel of the end bell — keep the ride running, do not reschedule.
    func suppressEndBell(sessionID: UUID) {
        suppressedEndBellSessionIDs.insert(sessionID)
        alarmScheduler.cancel(sessionID: sessionID)
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
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        // Reschedule from remaining time — do not resume a paused AlarmKit countdown.
        refreshEndBell(for: session, now: now)
    }

    /// StandBy / system AlarmKit resume is no longer a Live Activity path (paused alarms are cancelled).
    /// Kept for tests / defensive sync if a template UI still resumes.
    func resumeFromAlarmKit(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen, session.isPaused else { return }
        session.pausedAt = nil
        session.segmentStartedAt = now
        phase = .running
        try save()
        reconcile(now: now)
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        refreshEndBell(for: session, now: now)
    }

    func extend(by seconds: TimeInterval, reason: String? = nil, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard !session.isPaused else {
            throw SessionError.notRunning
        }
        guard seconds > 0 else { return }

        let added = Int(seconds.rounded())
        session.budgetSecondsAtStart += added
        let record = SessionExtension(
            addedSeconds: added,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: now,
            session: session
        )
        modelContext.insert(record)
        suppressedEndBellSessionIDs.remove(session.id)
        try save()
        reconcile(now: now)
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        refreshEndBell(for: session, now: now)
    }

    func arrive(resolution: OvertimeResolution? = nil, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        if let resolution {
            session.overtimeResolution = resolution
        }
        try close(session: session, outcome: .arrived, closureKind: .arrived, now: now)
        enqueueArrivalMomentIfNeeded(session)
    }

    func partialDisembark(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        try close(session: session, outcome: .partialDisembark, closureKind: .partialDisembark, now: now)
    }

    func abandon(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        try close(session: session, outcome: .abandoned, closureKind: .abandoned, now: now)
    }

    func partialDisembark(session: WorkSession, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard session.isOpen else {
            throw SessionError.noActiveSession
        }
        try close(session: session, outcome: .partialDisembark, closureKind: .partialDisembark, now: now)
    }

    func abandon(session: WorkSession, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard session.isOpen else {
            throw SessionError.noActiveSession
        }
        try close(session: session, outcome: .abandoned, closureKind: .abandoned, now: now)
    }

    // MARK: - Physical deletion

    /// Removes a ticket and cascaded sessions from the store.
    /// Open sessions on the ticket are torn down (LA / alarms / activeSession) without archiving.
    func deleteTicket(_ ticket: Ticket, now: Date? = nil) throws {
        let now = now ?? clock.now
        for session in ticket.sessions where session.isOpen {
            tearDownOpenSessionSideEffects(session)
        }
        modelContext.delete(ticket)
        try save()
        reconcile(now: now)
    }

    /// Removes one ended history row. If the parent ticket has no sessions left, deletes the ticket too.
    func deleteEndedSession(_ session: WorkSession, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard TicketDeletion.canDeleteEndedSession(session) else {
            throw SessionError.cannotDeleteOpenSession
        }
        let ticket = session.ticket
        let remainingIDs = ticket?.sessions.map(\.id) ?? []
        let shouldDeleteTicket = ticket != nil
            && TicketDeletion.shouldDeleteOrphanTicket(
                remainingSessionIDs: remainingIDs,
                removing: session.id
            )
        modelContext.delete(session)
        if shouldDeleteTicket, let ticket {
            modelContext.delete(ticket)
        }
        try save()
        reconcile(now: now)
    }

    func restoreDeletedTicket(_ record: DeletionUndo.TicketRecord) throws {
        try DeletionUndo.restoreTicket(record, into: modelContext)
        try save()
        try recoverOnLaunch()
    }

    func restoreDeletedSession(_ record: DeletionUndo.SessionRecord) throws {
        DeletionUndo.restoreSession(record, onto: nil, into: modelContext)
        try save()
        try recoverOnLaunch()
    }

    func restoreDeletedTag(_ record: DeletionUndo.TagRecord) throws {
        DeletionUndo.restoreTag(record, into: modelContext)
        try save()
    }

    func consumePunctualityMoment() {
        guard !punctualityQueue.isEmpty else { return }
        punctualityQueue.removeFirst()
    }

    /// Clears in-memory / external side effects for an open session without writing closure fields.
    private func tearDownOpenSessionSideEffects(_ session: WorkSession) {
        if activeSession?.id == session.id {
            activeSession = nil
            phase = .idle
        }
        overtimeNotifier.cancel(sessionID: session.id)
        liveActivityManager.end()
        alarmScheduler.cancel(sessionID: session.id)
        suppressedEndBellSessionIDs.remove(session.id)
    }

    private func close(
        session: WorkSession,
        outcome: SessionOutcome,
        closureKind: ClosureKind,
        now: Date
    ) throws {
        if !session.isPaused, let segmentStartedAt = session.segmentStartedAt {
            session.accumulatedActiveSeconds += now.timeIntervalSince(segmentStartedAt)
            session.segmentStartedAt = nil
        }
        session.pausedAt = nil
        session.endedAt = now
        session.outcome = outcome

        if let ticket = session.ticket {
            ticket.closedAt = now
            ticket.closureKind = closureKind
        }

        if activeSession?.id == session.id {
            activeSession = nil
            phase = .idle
        }
        overtimeNotifier.cancel(sessionID: session.id)
        liveActivityManager.end()
        alarmScheduler.cancel(sessionID: session.id)
        suppressedEndBellSessionIDs.remove(session.id)
        try save()
        reconcile(now: now)
    }

    // MARK: - Lifecycle

    func reconcile(now: Date? = nil) {
        let now = now ?? clock.now
        defer { publishWidgetSnapshot(at: now) }

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
                liveActivityManager.end()
                return
            }
            return reconcile(now: now)
        }

        if session.isPaused {
            phase = .paused
            liveActivityManager.end()
            return
        }

        let nextPhase: SessionPhase = session.remainingSeconds(at: now) <= 0 ? .overtime : .running
        let crossedIntoOvertime = phase != .overtime && nextPhase == .overtime
        phase = nextPhase
        if crossedIntoOvertime {
            refreshLiveActivity(for: session, now: now)
        }
    }

    func recoverOnLaunch() throws {
        let now = clock.now
        let todayKey = ServiceDay.dayKey(for: now, calendar: calendar)

        let openDays = fetchOpenServiceDays()
        if openDays.count > 1 {
            // Keep the newest open day; close stale duplicates.
            let sorted = openDays.sorted { $0.startedAt > $1.startedAt }
            for stale in sorted.dropFirst() {
                stale.endedAt = now
            }
        }

        if let openDay = fetchOpenServiceDay() {
            activeServiceDay = openDay
            needsServiceDayEndPrompt = openDay.calendarDayKey != todayKey
        } else {
            activeServiceDay = nil
            needsServiceDayEndPrompt = false
        }

        // Only collapse duplicate *running* sessions. Multiple paused sessions are allowed.
        let runningSessions = fetchOpenSessions().filter { !$0.isPaused }
        if runningSessions.count > 1 {
            let sorted = runningSessions.sorted { $0.startedAt > $1.startedAt }
            for stale in sorted.dropFirst() {
                if let segmentStartedAt = stale.segmentStartedAt {
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
        if let session = activeSession, session.isOpen, !session.isPaused {
            // Tear down any leftover paused/orphan AlarmKit LAs from prior rides.
            alarmScheduler.cancelAllExcept(sessionID: session.id)
            refreshOvertimeNotification(for: session, now: now)
            refreshLiveActivity(for: session, now: now)
            refreshEndBell(for: session, now: now)
        } else if let session = activeSession, session.isOpen, session.isPaused {
            // Paused rides must not keep an AlarmKit Live Activity.
            liveActivityManager.end()
            overtimeNotifier.cancel(sessionID: session.id)
            alarmScheduler.cancelAll()
        } else {
            liveActivityManager.end()
            alarmScheduler.cancelAll()
        }
        refreshTodayOverrideCount(at: now)
    }

    /// Settings toggle for end bell — apply immediately to the active ride.
    func syncEndBellWithSettings(now: Date? = nil) {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            alarmScheduler.cancelAll()
            liveActivityManager.end()
            publishWidgetSnapshot(at: now)
            return
        }
        if settings.endBellEnabled {
            // AlarmKit owns StandBy countdown — tear down Session LA.
            liveActivityManager.end()
            refreshEndBell(for: session, now: now)
        } else {
            alarmScheduler.cancel(sessionID: session.id)
            suppressedEndBellSessionIDs.remove(session.id)
            refreshLiveActivity(for: session, now: now)
        }
        publishWidgetSnapshot(at: now)
    }

    // MARK: - Queries

    private func refreshTodayOverrideCount(at now: Date) {
        let dayKey = ServiceDay.dayKey(for: now, calendar: calendar)
        todayOverrideCount = overrideCounter.count(forDayKey: dayKey)
    }

    private func refreshLiveActivity(for session: WorkSession, now: Date) {
        // One LA at a time: AlarmKit StandBy countdown replaces Session LA.
        if settings.endBellEnabled {
            liveActivityManager.end()
            return
        }
        guard session.isOpen, !session.isPaused else {
            liveActivityManager.end()
            return
        }
        let title = session.ticket?.title ?? "切符"
        let deadline = now.addingTimeInterval(session.remainingSeconds(at: now))
        liveActivityManager.startOrUpdate(
            sessionID: session.id,
            title: title,
            deadline: deadline,
            isOvertime: session.remainingSeconds(at: now) <= 0,
            budgetSeconds: session.budgetSecondsAtStart
        )
    }

    private func publishWidgetSnapshot(at now: Date) {
        let dayKey = ServiceDay.dayKey(for: now, calendar: calendar)
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
        var focusSeconds: TimeInterval = 0
        for session in sessions {
            let anchor = session.endedAt ?? session.startedAt
            guard ServiceDay.dayKey(for: anchor, calendar: calendar) == dayKey else { continue }
            if session.isOpen, !session.isPaused {
                focusSeconds += session.elapsedSeconds(at: now)
            } else {
                focusSeconds += session.accumulatedActiveSeconds
            }
        }
        WidgetSnapshotStore.publish(
            isInService: isInService,
            pausedCount: pausedTicketCount,
            focusMinutesToday: Int((focusSeconds / 60).rounded()),
            now: now
        )
    }

    private func refreshEndBell(for session: WorkSession, now: Date) {
        guard settings.endBellEnabled else {
            alarmScheduler.cancel(sessionID: session.id)
            return
        }
        guard session.isOpen else {
            alarmScheduler.cancel(sessionID: session.id)
            return
        }
        // User dismissed the bell from StandBy — do not resurrect it.
        guard !suppressedEndBellSessionIDs.contains(session.id) else { return }
        // Paused sessions never keep an AlarmKit Live Activity.
        guard !session.isPaused else {
            alarmScheduler.cancel(sessionID: session.id)
            return
        }
        let elapsed = session.elapsedSeconds(at: now)
        guard let fireAt = SessionEndSchedule.fireAt(
            budgetSeconds: session.budgetSecondsAtStart,
            elapsedSeconds: elapsed,
            now: now
        ) else {
            alarmScheduler.cancel(sessionID: session.id)
            return
        }
        let title = session.ticket?.title ?? "切符"
        alarmScheduler.scheduleEndBell(
            sessionID: session.id,
            ticketTitle: title,
            fireAt: fireAt,
            budgetSeconds: session.budgetSecondsAtStart
        )
    }

    private func refreshOvertimeNotification(for session: WorkSession, now: Date) {
        guard session.isOpen, !session.isPaused else {
            overtimeNotifier.cancel(sessionID: session.id)
            return
        }
        // When AlarmKit owns the end signal, do not also schedule a local notification.
        let channel = EndBellDelivery.channel(
            endBellEnabled: settings.endBellEnabled,
            alarmKitAuthorized: alarmScheduler.isAuthorized
        )
        guard channel == .localNotification else {
            overtimeNotifier.cancel(sessionID: session.id)
            return
        }
        let elapsed = session.elapsedSeconds(at: now)
        guard let fireAt = OvertimeSchedule.fireAt(
            budgetSeconds: session.budgetSecondsAtStart,
            elapsedSeconds: elapsed,
            now: now
        ) else {
            overtimeNotifier.cancel(sessionID: session.id)
            return
        }
        let title = session.ticket?.title ?? "切符"
        overtimeNotifier.schedule(sessionID: session.id, ticketTitle: title, fireAt: fireAt)
    }

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
        fetchOpenServiceDays().first
    }

    private func fetchOpenServiceDays() -> [ServiceDay] {
        let descriptor = FetchDescriptor<ServiceDay>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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

    private func enqueueArrivalMomentIfNeeded(_ session: WorkSession) {
        guard Punctuality.shouldCelebrateArrival(outcome: session.outcome) else { return }
        let title = session.ticket?.title ?? "切符"
        enqueuePunctualityMoment(
            PunctualityMoment(
                kind: .arrival(
                    title: title,
                    estimateSeconds: session.estimatedSecondsAtStart,
                    actualSeconds: session.accumulatedActiveSeconds,
                    punctuality: Punctuality.classify(session)
                )
            )
        )
    }

    private func enqueuePunctualityMoment(_ moment: PunctualityMoment) {
        punctualityQueue.append(moment)
        // Arrival haptic is owned by ArrivalInvalidateOverlay (user swipe).
        // 定時運行 keeps a brief success cue on enqueue.
        if case .onTimeService = moment.kind {
            punctualityHapticTick += 1
        }
    }

    /// Arrivals closed during this service window (startedAt ... endedBy).
    private func arrivedSessions(inServiceDay day: ServiceDay, endedBy end: Date) -> [WorkSession] {
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

    private func save() throws {
        try modelContext.save()
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
