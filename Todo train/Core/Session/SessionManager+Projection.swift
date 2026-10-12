//
//  SessionManager+Projection.swift
//  Todo train
//
//  Read-side projections for Hub / Focus. Write commands stay in the other
//  SessionManager+* files. Chrome setters forward to SessionPresentation.
//

import Foundation

extension SessionManager {
    /// Forwards to `presentation`. Timetable and Boarding still assign these.
    /// Migrated views read `presentation` directly. Tests read the getters.
    var punctualityQueue: [PunctualityMoment] {
        get { presentation.punctualityQueue }
        set { presentation.punctualityQueue = newValue }
    }

    var punctualityHapticTick: Int {
        get { presentation.punctualityHapticTick }
        set { presentation.punctualityHapticTick = newValue }
    }

    var checkInHapticTick: Int {
        get { presentation.checkInHapticTick }
        set { presentation.checkInHapticTick = newValue }
    }

    var timetableQuietMessage: String? {
        get { presentation.timetableQuietMessage }
        set { presentation.timetableQuietMessage = newValue }
    }

    var punctualityMoment: PunctualityMoment? { presentation.punctualityMoment }

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

    /// 停車上限の分子。ATS が停めた枠は占有中は数えない。
    var pausedCountTowardLimit: Int {
        PauseLimitGuard.pausedCountTowardLimit(isHeld: pausedSessions.map(\.timetableHeld))
    }

    /// Open sessions that are currently paused (for Hub resume UI).
    var pausedSessions: [WorkSession] {
        openPausedSessions()
    }

    var isInService: Bool {
        guard let activeServiceDay, activeServiceDay.isOpen else { return false }
        return activeServiceDay.calendarDayKey == ServiceDay.dayKey(for: clock.now, calendar: calendar)
    }

    /// Shared with Hub chrome. Uses the same running-session truth as `board()`.
    var boardingEligibility: BoardingEligibility {
        BoardingEligibility.evaluate(
            isInService: isInService,
            needsServiceDayEnd: needsServiceDayEndPrompt,
            hasRunningRide: fetchRunningSession() != nil,
            passengerLocksDriving: passengerChrome.locksDriving || fetchOpenPassengerRide() != nil,
            canBoardNewRide: PauseLimitGuard.canBoardNewRide(
                pausedCount: pausedCountTowardLimit,
                limit: pauseLimit
            )
        )
    }
}
