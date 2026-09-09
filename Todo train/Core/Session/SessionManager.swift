//
//  SessionManager.swift
//  Todo train
//

import Foundation
import Observation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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
    private let checkInNotifier: any CheckInNotifying
    private let coachingEngine: any CoachingEngine
    private let overrideCounter: any OverrideCounting
    private let liveActivityManager: any LiveActivityManaging
    private let alarmScheduler: any AlarmScheduling
    private let deviceIdentity: any DeviceIdentifying
    private let deviceLock: any DeviceLockReading

    private var awayFireTask: Task<Void, Never>?
    #if canImport(UIKit)
    private var awayBackgroundTask = UIBackgroundTaskIdentifier.invalid
    #endif

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
    /// Bumps when a 車内放送 panel appears.
    private(set) var checkInHapticTick: Int = 0

    var punctualityMoment: PunctualityMoment? { punctualityQueue.first }

    var pauseLimit: Int { settings.pauseLimit }

    var pendingCheckIn: CheckInKind? { activeSession?.pendingCheckIn }

    /// Focus cover is only for a ride boarded on this device.
    var shouldPresentFocusCover: Bool {
        (phase == .running || phase == .overtime) && ownsActiveRide
    }

    /// `nil` boardedDeviceID is legacy local data — treat as this device.
    var ownsActiveRide: Bool {
        guard let activeSession else { return false }
        return ownsDeviceSideEffects(activeSession)
    }

    var checkInPromptLine: String {
        if let line = activeSession?.checkInPromptLine, !line.isEmpty {
            return line
        }
        return CheckInCopy.fallback(title: activeSession?.ticket?.title ?? "")
    }

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
        checkInNotifier: (any CheckInNotifying)? = nil,
        coachingEngine: (any CoachingEngine)? = nil,
        overrideCounter: (any OverrideCounting)? = nil,
        liveActivityManager: (any LiveActivityManaging)? = nil,
        alarmScheduler: (any AlarmScheduling)? = nil,
        deviceIdentity: (any DeviceIdentifying)? = nil,
        deviceLock: (any DeviceLockReading)? = nil
    ) {
        self.modelContext = modelContext
        self.clock = clock
        self.calendar = calendar
        self.settings = settings
        self.overtimeNotifier = overtimeNotifier ?? NoOpOvertimeNotifier()
        self.checkInNotifier = checkInNotifier ?? NoOpCheckInNotifier()
        self.coachingEngine = coachingEngine ?? HeuristicCoachingEngine()
        self.overrideCounter = overrideCounter ?? OverrideCounter.shared
        self.liveActivityManager = liveActivityManager ?? NoOpLiveActivityManager()
        self.alarmScheduler = alarmScheduler ?? NoOpAlarmScheduler()
        self.deviceIdentity = deviceIdentity ?? SystemDeviceIdentity()
        self.deviceLock = deviceLock ?? SystemDeviceLock()
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
        checkInNotifier.requestAuthorizationIfNeeded()
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
        checkInNotifier.cancelAll()
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

        guard PauseLimitGuard.canBoardNewRide(
            pausedCount: pausedTicketCount,
            limit: settings.pauseLimit
        ) else {
            throw SessionError.pauseLimitReached
        }

        try startNewSession(ticket: ticket, now: now)
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

            if let paused = openPausedSessions().first(where: { $0.ticket?.id == ticket.id }) {
                try parkRunningSessionForSwitch(running, now: now)
                activeSession = paused
                try resume(now: now)
                return
            }

            // Gate on paused tickets already sitting, before parking the current ride.
            guard PauseLimitGuard.canBoardNewRide(
                pausedCount: pausedTicketCount,
                limit: settings.pauseLimit
            ) else {
                throw SessionError.pauseLimitReached
            }

            try parkRunningSessionForSwitch(running, now: now)
            try startNewSession(ticket: ticket, now: now)
            return
        }

        try board(ticket: ticket, now: now)
    }

    private func startNewSession(ticket: Ticket, now: Date) throws {
        let estimate = min(max(ticket.estimatedSeconds, 1), Ticket.maxEstimatedSeconds)
        let session = WorkSession(
            startedAt: now,
            estimatedSecondsAtStart: estimate,
            ticket: ticket,
            boardedDeviceID: deviceIdentity.id
        )
        modelContext.insert(session)
        applyCheckInSchedule(to: session, title: ticket.title, estimatedSeconds: estimate)
        activeSession = session
        phase = .running
        try save()
        // One LA / Alarm at a time — drop the previous paused ride's presentation.
        alarmScheduler.cancelAllExcept(sessionID: session.id)
        reconcile(now: now)
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        refreshEndBell(for: session, now: now)
        refreshProgressCheckInNotifications(for: session, now: now)
        requestCheckInPrompt(for: session, title: ticket.title, estimatedMinutes: estimate / 60)
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

        try applyPause(session: session, now: now)
    }

    /// Pause is always allowed. Kept for older call sites; no longer increments override.
    @discardableResult
    func forcePause(now: Date? = nil) throws -> Int {
        try pause(now: now)
        return todayOverrideCount
    }

    private func applyPause(session: WorkSession, now: Date, syncAlarm: Bool = true) throws {
        if let segmentStartedAt = session.segmentStartedAt {
            session.accumulatedActiveSeconds += now.timeIntervalSince(segmentStartedAt)
        }
        session.segmentStartedAt = nil
        session.pausedAt = now
        beginPauseRecord(on: session, now: now)
        session.pendingCheckIn = nil
        session.awayDueAt = nil
        phase = .paused
        overtimeNotifier.cancel(sessionID: session.id)
        checkInNotifier.cancel(sessionID: session.id)
        cancelAwayFireTask()
        if syncAlarm {
            if isAlarmKitEndBellActive {
                alarmScheduler.pause(sessionID: session.id)
            } else {
                alarmScheduler.cancel(sessionID: session.id)
            }
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
        beginPauseRecord(on: session, now: now)
        session.pendingCheckIn = nil
        session.awayDueAt = nil
        overtimeNotifier.cancel(sessionID: session.id)
        checkInNotifier.cancel(sessionID: session.id)
        cancelAwayFireTask()
        liveActivityManager.end()
        alarmScheduler.cancel(sessionID: session.id)
        try save()
    }

    private func beginPauseRecord(on session: WorkSession, now: Date) {
        if session.pauses.contains(where: { $0.endedAt == nil }) { return }
        let record = SessionPause(startedAt: now, session: session)
        modelContext.insert(record)
    }

    private func endOpenPauseRecord(on session: WorkSession, now: Date) {
        for pause in session.pauses where pause.endedAt == nil {
            pause.endedAt = now
        }
    }

    /// StandBy / system AlarmKit pause → mirror into the open session (no AlarmKit echo).
    func pauseFromAlarmKit(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        try applyPause(session: session, now: now, syncAlarm: false)
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

        endOpenPauseRecord(on: session, now: now)
        session.pausedAt = nil
        session.segmentStartedAt = now
        phase = .running
        try save()
        alarmScheduler.cancelAllExcept(sessionID: session.id)
        let resumedAlarm = isAlarmKitEndBellActive && alarmScheduler.resume(sessionID: session.id)
        reconcile(now: now)
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        if !resumedAlarm {
            refreshEndBell(for: session, now: now)
        }
        refreshProgressCheckInNotifications(for: session, now: now)
    }

    /// StandBy / system AlarmKit resume → mirror into the open session (no AlarmKit echo).
    func resumeFromAlarmKit(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen, session.isPaused else { return }
        endOpenPauseRecord(on: session, now: now)
        session.pausedAt = nil
        session.segmentStartedAt = now
        phase = .running
        try save()
        reconcile(now: now)
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        refreshProgressCheckInNotifications(for: session, now: now)
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
        refreshProgressCheckInNotifications(for: session, now: now)
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

    /// 車内放送 4 択. `willExtend` only acknowledges; Focus shows the extend panel.
    func answerCheckIn(_ answer: CheckInAnswerKind, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard session.pendingCheckIn != nil else { return }

        consumePendingCheckIn(session, answer: answer, now: now)
        session.awayDueAt = nil
        try save()

        switch answer {
        case .stillOnIt, .willExtend:
            reconcile(now: now)
            refreshProgressCheckInNotifications(for: session, now: now)
        case .paused:
            try pause(now: now)
        case .alreadyDone:
            try arrive(resolution: .alreadyDone, now: now)
        }
    }

    /// Unlocked background only. Locked / end-bell LA / cabin-off: no away watch.
    func beginAwayWatch(now: Date? = nil) {
        if deviceLock.isLocked {
            cancelAwayWatch(now: now)
            return
        }
        let now = now ?? clock.now
        guard settings.cabinAnnouncementsEnabled else { return }
        guard awayInterruptChannel != .none else { return }
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        guard ownsDeviceSideEffects(session) else { return }
        guard session.remainingSeconds(at: now) > 0 else { return }
        guard session.pendingCheckIn == nil else { return }
        guard session.awayDueAt == nil else { return }

        let delay = CheckInScheduling.awayDelay(
            seed: session.id,
            salt: UInt64(session.checkInFiredCount) &+ 99
        )
        let fireAt = now.addingTimeInterval(delay)
        session.awayDueAt = fireAt
        try? save()
        if awayInterruptChannel == .localNotification {
            checkInNotifier.scheduleAway(
                sessionID: session.id,
                ticketTitle: session.ticket?.title ?? "切符",
                body: CheckInCopy.away,
                fireAt: fireAt
            )
        }
        armAwayFire(at: fireAt, sessionID: session.id)
    }

    /// Lock screen: drop the watch. Do not promote a pending `.away` panel.
    func cancelAwayWatch(now: Date? = nil) {
        let now = now ?? clock.now
        cancelAwayFireTask()
        guard let session = activeSession, session.isOpen else { return }
        var changed = false
        if session.awayDueAt != nil {
            session.awayDueAt = nil
            changed = true
        }
        if session.pendingCheckIn == .away {
            session.pendingCheckIn = nil
            changed = true
        }
        if changed { try? save() }
        checkInNotifier.cancel(sessionID: session.id)
        if !session.isPaused, session.remainingSeconds(at: now) > 0, ownsDeviceSideEffects(session) {
            refreshProgressCheckInNotifications(for: session, now: now)
            refreshLiveActivity(for: session, now: now)
        }
    }

    /// Foreground: clear the watch without turning away into a Focus 4-choice.
    func endAwayWatch(now: Date? = nil) {
        let now = now ?? clock.now
        cancelAwayWatch(now: now)
        reconcile(now: now)
    }

    func handleCheckInNotification(identifier: String, action: String) {
        guard CheckInNotification.isCheckIn(identifier) else { return }
        reconcile()
        guard ownsActiveRide else { return }
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        guard session.remainingSeconds(at: clock.now) > CheckInScheduling.overtimeGuardSeconds else { return }

        let isAway = CheckInNotification.isAway(identifier)
        if isAway {
            if action == CheckInNotification.pauseAction {
                try? pause()
            }
            return
        }

        if session.pendingCheckIn == nil {
            session.pendingCheckIn = .progress
            if session.awayDueAt != nil {
                session.awayDueAt = nil
                cancelAwayFireTask()
            }
            checkInHapticTick += 1
            try? save()
        }

        switch action {
        case CheckInNotification.pauseAction:
            try? answerCheckIn(.paused)
        case CheckInNotification.stillOnItAction:
            guard session.pendingCheckIn == .progress else { return }
            try? answerCheckIn(.stillOnIt)
        default:
            break
        }
    }

    func pauseRide(sessionID: UUID) {
        guard activeSession?.id == sessionID else { return }
        try? pause()
    }

    /// Settings toggle for 車内放送 — apply immediately to the active ride.
    func syncCabinAnnouncementsWithSettings(now: Date? = nil) {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            checkInNotifier.cancelAll()
            return
        }
        guard ownsDeviceSideEffects(session) else {
            checkInNotifier.cancelAll()
            return
        }
        if !settings.cabinAnnouncementsEnabled {
            session.pendingCheckIn = nil
            session.awayDueAt = nil
            cancelAwayFireTask()
            checkInNotifier.cancel(sessionID: session.id)
            try? save()
            reconcile(now: now)
            return
        }
        if !session.isPaused {
            refreshProgressCheckInNotifications(for: session, now: now)
        }
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
        checkInNotifier.cancel(sessionID: session.id)
        cancelAwayFireTask()
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
        endOpenPauseRecord(on: session, now: now)
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
        checkInNotifier.cancel(sessionID: session.id)
        cancelAwayFireTask()
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
            if PauseLiveActivityRetention.isExpired(pausedAt: session.pausedAt, now: now) {
                liveActivityManager.end()
                overtimeNotifier.cancel(sessionID: session.id)
                alarmScheduler.cancel(sessionID: session.id)
            } else {
                refreshLiveActivity(for: session, now: now)
            }
            return
        }

        let nextPhase: SessionPhase = session.remainingSeconds(at: now) <= 0 ? .overtime : .running
        let crossedIntoOvertime = phase != .overtime && nextPhase == .overtime
        phase = nextPhase
        if ownsDeviceSideEffects(session) {
            if crossedIntoOvertime {
                skipPendingCheckInForOvertime(session)
                refreshLiveActivity(for: session, now: now)
            } else if nextPhase == .running {
                refreshPendingCheckIn(session, now: now)
            }
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
        let pendingKind = applyPendingLiveActivityAction()
        reconcile(now: now)
        refreshOwnedDeviceSideEffects(now: now, pendingKind: pendingKind)
        refreshTodayOverrideCount(at: now)
    }

    /// CloudKit remote save. Do not call `recoverOnLaunch` (that re-schedules dismissed end bells).
    func handleRemoteStoreChange(now: Date? = nil) {
        guard CloudKitSync.isConfigured else { return }
        let now = now ?? clock.now
        reconcile(now: now)
        refreshOwnedDeviceSideEffects(now: now)
    }

    /// Consume pause/resume handoff from Live Activity intents (app may have been killed).
    @discardableResult
    func applyPendingLiveActivityAction() -> FocusPendingActionKind? {
        guard let pending = FocusPendingActionStore.peek() else { return nil }
        switch pending.kind {
        case .pause, .resume:
            _ = FocusPendingActionStore.consume()
            guard pending.sessionID == activeSession?.id else { return nil }
            if pending.kind == .pause {
                try? pauseFromAlarmKit()
            } else {
                try? resumeFromAlarmKit()
            }
            return pending.kind
        case .arrive, .extend:
            return nil
        }
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
        guard ownsDeviceSideEffects(session) else {
            alarmScheduler.cancelAll()
            liveActivityManager.end()
            publishWidgetSnapshot(at: now)
            return
        }
        if session.isPaused {
            if settings.endBellEnabled {
                liveActivityManager.end()
            } else {
                alarmScheduler.cancel(sessionID: session.id)
                suppressedEndBellSessionIDs.remove(session.id)
                refreshLiveActivity(for: session, now: now)
            }
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

    // MARK: - Check-in

    private func applyCheckInSchedule(to session: WorkSession, title: String, estimatedSeconds: Int) {
        session.checkInOffsetSeconds = CheckInScheduling.offsets(
            estimatedSeconds: estimatedSeconds,
            seed: session.id
        )
        session.checkInFiredCount = 0
        session.pendingCheckInKindRaw = nil
        session.awayDueAt = nil
        session.checkInPromptLine = CheckInCopy.fallback(title: title)
        session.checkInAnswersJSON = "[]"
    }

    private func requestCheckInPrompt(for session: WorkSession, title: String, estimatedMinutes: Int) {
        guard settings.cabinAnnouncementsEnabled else { return }
        guard ownsDeviceSideEffects(session) else { return }
        let sessionID = session.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            let lines = await self.coachingEngine.checkInLines(
                title: title,
                estimatedMinutes: estimatedMinutes
            )
            guard let line = lines.first.map(Self.sanitizeCheckInLine), !line.isEmpty else { return }
            guard let current = self.activeSession, current.id == sessionID, current.isOpen else { return }
            current.checkInPromptLine = line
            try? self.save()
            self.refreshProgressCheckInNotifications(for: current, now: self.clock.now)
        }
    }

    private static func sanitizeCheckInLine(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        if collapsed.count <= 40 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 40)
        return String(collapsed[..<end])
    }

    private func consumePendingCheckIn(
        _ session: WorkSession,
        answer: CheckInAnswerKind,
        now: Date
    ) {
        guard let kind = session.pendingCheckIn else { return }
        var answers = session.checkInAnswers
        answers.append(CheckInAnswerRecord(kind: kind, answer: answer, answeredAt: now))
        session.checkInAnswers = answers
        if kind == .progress {
            session.checkInFiredCount += 1
        }
        session.pendingCheckIn = nil
    }

    private func skipPendingCheckInForOvertime(_ session: WorkSession) {
        if session.pendingCheckIn == .progress {
            session.checkInFiredCount += 1
        }
        session.pendingCheckIn = nil
        session.awayDueAt = nil
        cancelAwayFireTask()
        checkInNotifier.cancel(sessionID: session.id)
        try? save()
    }

    private func refreshPendingCheckIn(_ session: WorkSession, now: Date) {
        guard ownsDeviceSideEffects(session) else { return }
        guard settings.cabinAnnouncementsEnabled else {
            if session.pendingCheckIn != nil || session.awayDueAt != nil {
                session.pendingCheckIn = nil
                session.awayDueAt = nil
                cancelAwayFireTask()
                checkInNotifier.cancel(sessionID: session.id)
                try? save()
            }
            return
        }

        let remaining = session.remainingSeconds(at: now)
        if remaining <= CheckInScheduling.overtimeGuardSeconds {
            return
        }

        if session.pendingCheckIn != nil {
            return
        }

        let elapsed = session.elapsedSeconds(at: now)
        if CheckInScheduling.dueProgressOffset(
            offsets: session.checkInOffsets,
            firedCount: session.checkInFiredCount,
            elapsedSeconds: elapsed,
            remainingSeconds: remaining,
            hasPending: false
        ) != nil {
            session.pendingCheckIn = .progress
            session.awayDueAt = nil
            cancelAwayFireTask()
            checkInHapticTick += 1
            try? save()
            return
        }

        if let due = session.awayDueAt, due <= now {
            fireAwayInterrupt(session, now: now, presentAlert: true)
        }
    }

    private func refreshProgressCheckInNotifications(for session: WorkSession, now: Date) {
        guard ownsDeviceSideEffects(session) else {
            checkInNotifier.cancel(sessionID: session.id)
            return
        }
        guard settings.cabinAnnouncementsEnabled else {
            checkInNotifier.cancel(sessionID: session.id)
            return
        }
        guard session.isOpen, !session.isPaused else {
            checkInNotifier.cancel(sessionID: session.id)
            return
        }
        let elapsed = session.elapsedSeconds(at: now)
        let body = session.checkInPromptLine ?? CheckInCopy.fallback(title: session.ticket?.title ?? "")
        let title = session.ticket?.title ?? "切符"
        for (index, offset) in session.checkInOffsets.enumerated() {
            guard index >= session.checkInFiredCount else { continue }
            guard let fireAt = CheckInScheduling.wallFireAt(
                offset: offset,
                elapsedSeconds: elapsed,
                now: now
            ) else { continue }
            checkInNotifier.scheduleProgress(
                sessionID: session.id,
                index: index,
                ticketTitle: title,
                body: body,
                fireAt: fireAt
            )
        }
    }

    // MARK: - Queries

    /// Alarms / LA / 車内放送 are local-device only. `nil` is pre-CloudKit local data.
    private func ownsDeviceSideEffects(_ session: WorkSession) -> Bool {
        guard let boarded = session.boardedDeviceID else { return true }
        return boarded == deviceIdentity.id
    }

    /// Refresh or tear down device-local effects after launch / remote change.
    /// Does not collapse duplicate sessions (that stays in `recoverOnLaunch`).
    private func refreshOwnedDeviceSideEffects(now: Date, pendingKind: FocusPendingActionKind? = nil) {
        guard let session = activeSession, session.isOpen else {
            liveActivityManager.end()
            alarmScheduler.cancelAll()
            return
        }
        guard ownsDeviceSideEffects(session) else {
            liveActivityManager.end()
            overtimeNotifier.cancel(sessionID: session.id)
            checkInNotifier.cancel(sessionID: session.id)
            alarmScheduler.cancel(sessionID: session.id)
            return
        }
        if session.isPaused {
            overtimeNotifier.cancel(sessionID: session.id)
            checkInNotifier.cancel(sessionID: session.id)
            if PauseLiveActivityRetention.isExpired(pausedAt: session.pausedAt, now: now) {
                liveActivityManager.end()
                alarmScheduler.cancelAll()
            } else {
                alarmScheduler.cancelAllExcept(sessionID: session.id)
                refreshLiveActivity(for: session, now: now)
            }
            return
        }
        alarmScheduler.cancelAllExcept(sessionID: session.id)
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        if pendingKind == .resume, alarmScheduler.hasAlarm(sessionID: session.id) {
            _ = alarmScheduler.resume(sessionID: session.id)
        } else {
            refreshEndBell(for: session, now: now)
        }
        refreshProgressCheckInNotifications(for: session, now: now)
    }

    private func refreshTodayOverrideCount(at now: Date) {
        let dayKey = ServiceDay.dayKey(for: now, calendar: calendar)
        todayOverrideCount = overrideCounter.count(forDayKey: dayKey)
    }

    private func refreshLiveActivity(for session: WorkSession, now: Date, presentAwayAlert: Bool = false) {
        guard ownsDeviceSideEffects(session) else {
            liveActivityManager.end()
            return
        }
        // One LA at a time: AlarmKit StandBy countdown replaces Session LA.
        if isAlarmKitEndBellActive {
            liveActivityManager.end()
            return
        }
        guard session.isOpen else {
            liveActivityManager.end()
            return
        }
        if session.isPaused,
           PauseLiveActivityRetention.isExpired(pausedAt: session.pausedAt, now: now) {
            liveActivityManager.end()
            return
        }
        let remaining = session.remainingSeconds(at: now)
        let title = session.ticket?.title ?? "切符"
        let deadline = now.addingTimeInterval(remaining)
        let awayPrompt = (!session.isPaused && session.pendingCheckIn == .away) ? CheckInCopy.away : nil
        liveActivityManager.startOrUpdate(
            LiveActivitySessionContent(
                sessionID: session.id,
                title: title,
                deadline: deadline,
                isOvertime: remaining <= 0 && !session.isPaused,
                budgetSeconds: session.budgetSecondsAtStart,
                isPaused: session.isPaused,
                pausedAt: session.pausedAt,
                checkInPrompt: awayPrompt,
                alertTitle: presentAwayAlert ? CheckInCopy.away : nil,
                alertBody: presentAwayAlert ? title : nil
            )
        )
    }

    private var awayInterruptChannel: AwayInterruptChannel {
        CheckInScheduling.awayInterruptChannel(
            cabinEnabled: settings.cabinAnnouncementsEnabled,
            alarmKitOwnsLiveActivity: isAlarmKitEndBellActive,
            sessionLiveActivityEnabled: liveActivityManager.areActivitiesEnabled
        )
    }

    private func fireAwayInterrupt(_ session: WorkSession, now: Date, presentAlert: Bool) {
        cancelAwayFireTask()
        session.awayDueAt = nil
        session.pendingCheckIn = .away
        try? save()
        refreshLiveActivity(for: session, now: now, presentAwayAlert: presentAlert)
    }

    private func armAwayFire(at date: Date, sessionID: UUID) {
        cancelAwayFireTask()
        // Tests inject FixedSessionClock and call `reconcile()` themselves.
        // A wall-clock sleep would keep the test runner alive for 45–90s.
        guard clock is SystemSessionClock else { return }
        #if canImport(UIKit)
        awayBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "todotrain.away") { [weak self] in
            self?.endAwayBackgroundTask()
        }
        #endif
        awayFireTask = Task { @MainActor [weak self] in
            let delay = date.timeIntervalSince(self?.clock.now ?? Date())
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.activeSession?.id == sessionID else { return }
            self.reconcile()
            self.endAwayBackgroundTask()
        }
    }

    private func cancelAwayFireTask() {
        awayFireTask?.cancel()
        awayFireTask = nil
        endAwayBackgroundTask()
    }

    private func endAwayBackgroundTask() {
        #if canImport(UIKit)
        guard awayBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(awayBackgroundTask)
        awayBackgroundTask = .invalid
        #endif
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
        guard ownsDeviceSideEffects(session) else {
            alarmScheduler.cancel(sessionID: session.id)
            return
        }
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
        // Keep a paused AlarmKit Live Activity; resume / retention / a new ride tears it down.
        guard !session.isPaused else { return }
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
        guard ownsDeviceSideEffects(session) else {
            overtimeNotifier.cancel(sessionID: session.id)
            return
        }
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

extension SessionManager: SessionRidePausing {}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
