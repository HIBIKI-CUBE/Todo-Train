//
//  SessionManager.swift
//  Todo train
//

import Foundation
import Observation
import SwiftData
import TodoTrainSync
#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
final class SessionManager {
    var phase: SessionPhase = .idle
    /// Bumps when the open ride changes so the Mac companion can push a snap.
    var companionSyncTick: Int = 0
    var activeServiceDay: ServiceDay?
    var activeSession: WorkSession?
    var needsServiceDayEndPrompt = false

    let modelContext: ModelContext
    let clock: any SessionClock
    let calendar: Calendar
    let settings: AppSettings
    let overtimeNotifier: any OvertimeNotifying
    let checkInNotifier: any CheckInNotifying
    let coachingEngine: any CoachingEngine
    let liveActivityManager: any LiveActivityManaging
    let alarmScheduler: any AlarmScheduling
    let deviceIdentity: any DeviceIdentifying
    let deviceLock: any DeviceLockReading

    var awayFireTask: Task<Void, Never>?
    var idleWatchTask: Task<Void, Never>?
    /// Avoid re-enqueueing the same idle banner on every `reconcile`.
    var idleLocalNotificationArmed = false
    #if canImport(UIKit)
    var awayBackgroundTask = UIBackgroundTaskIdentifier.invalid
    #endif

    /// Session IDs whose end bell was dismissed by the user (StandBy cancel).
    /// Prevents recover / foreground from silently re-scheduling the same bell.
    var suppressedEndBellSessionIDs: Set<UUID> = []

    /// Ephemeral moments. Not persisted, not a score.
    /// Arrival haptic is owned by `ArrivalInvalidateOverlay`; enqueue ticks only for 定時運行.
    var punctualityQueue: [PunctualityMoment] = []
    /// Bumps when a 定時運行 moment is enqueued (haptic). Consume must not tick.
    var punctualityHapticTick: Int = 0
    /// Bumps when a 車内放送 panel appears.
    var checkInHapticTick: Int = 0
    /// Ephemeral one-liner after ATS pause. Not a score.
    var timetableQuietMessage: String?
    /// Scene is active — used so tests can stay on a FixedSessionClock.
    var isSceneActive = true
    /// Paired Mac already shows 車内放送 on PiP — skip progress locals, keep away.
    var suppressProgressLocalNotifications = false
    /// Today's 掲示. Membership stays on `TimetableBlock`.
    var noticeOccurrences: [CalendarOccurrence] = []
    let calendarBoard: any CalendarBoardReading

    var punctualityMoment: PunctualityMoment? { punctualityQueue.first }

    var pauseLimit: Int { settings.pauseLimit }

    func bumpCompanionSync() {
        companionSyncTick += 1
    }

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
        settings: AppSettings? = nil,
        overtimeNotifier: (any OvertimeNotifying)? = nil,
        checkInNotifier: (any CheckInNotifying)? = nil,
        coachingEngine: (any CoachingEngine)? = nil,
        liveActivityManager: (any LiveActivityManaging)? = nil,
        alarmScheduler: (any AlarmScheduling)? = nil,
        deviceIdentity: (any DeviceIdentifying)? = nil,
        deviceLock: (any DeviceLockReading)? = nil,
        calendarBoard: (any CalendarBoardReading)? = nil
    ) {
        self.modelContext = modelContext
        self.clock = clock
        self.calendar = calendar
        self.settings = settings ?? .shared
        self.overtimeNotifier = overtimeNotifier ?? NoOpOvertimeNotifier()
        self.checkInNotifier = checkInNotifier ?? NoOpCheckInNotifier()
        self.coachingEngine = coachingEngine ?? HeuristicCoachingEngine()
        self.liveActivityManager = liveActivityManager ?? NoOpLiveActivityManager()
        self.alarmScheduler = alarmScheduler ?? NoOpAlarmScheduler()
        self.deviceIdentity = deviceIdentity ?? SystemDeviceIdentity()
        self.deviceLock = deviceLock ?? SystemDeviceLock()
        #if canImport(EventKit)
        self.calendarBoard = calendarBoard ?? EventKitCalendarBoard()
        #else
        self.calendarBoard = calendarBoard ?? NoOpCalendarBoard()
        #endif
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
}

extension SessionManager: SessionRidePausing {}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
