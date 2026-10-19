//
//  SessionManager+Boarding.swift
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
    // MARK: - Boarding

    /// Issue at the end of the open deck, then board. Riding interrupts without a confirm.
    /// A failed board deletes the new ticket so inventory-only issue does not stick.
    func issueAndBoard(title: String, estimatedSeconds: Int, now: Date? = nil) throws {
        let now = now ?? clock.now
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              (60...Ticket.maxEstimatedSeconds).contains(estimatedSeconds)
        else {
            throw SessionError.noActiveService
        }
        try refusePassengerDriving()
        try ensureServiceAllowsBoarding(at: now)
        guard PauseLimitGuard.canBoardNewRide(
            pausedCount: pausedCountTowardLimit,
            limit: settings.pauseLimit
        ) else {
            throw SessionError.pauseLimitReached
        }

        let ticket = try TicketIssuer.issue(
            title: trimmed,
            estimatedSeconds: estimatedSeconds,
            createdAt: now,
            into: modelContext
        )
        do {
            if fetchRunningSession() != nil {
                try switchBoard(ticket: ticket, now: now)
            } else {
                try board(ticket: ticket, now: now)
            }
        } catch {
            modelContext.delete(ticket)
            _ = saveBestEffort()
            throw error
        }
    }

    func board(
        ticket: Ticket,
        now: Date? = nil,
        startedFrom: RideStartOrigin = .other
    ) throws {
        let now = now ?? clock.now
        // Flags first, then the shared gate. Passenger and service-day errors
        // throw before a running session is adopted.
        syncServiceDayForBoarding(at: now)
        let gate = boardingEligibility
        try gate.assertBeforeAdoptingRunningSession()

        guard ticket.isOpen else {
            throw SessionError.ticketAlreadyClosed
        }

        if let running = fetchRunningSession() {
            activeSession = running
            reconcile(now: now)
            throw SessionError.alreadyBoarding
        }

        if let paused = openPausedSessions().first(where: { $0.ticket?.id == ticket.id }) {
            try gate.assertCanBoardOrResume()
            activeSession = paused
            try resume(now: now)
            return
        }

        try gate.assertCanStartNewRide()
        try startNewSession(ticket: ticket, now: now, startedFrom: startedFrom)
    }

    /// Pause the current ride in the store, then board `ticket`, without publishing `.paused`.
    /// Focus stays up (`ContentView` only covers `.running` / `.overtime`).
    func switchBoard(ticket: Ticket, now: Date? = nil) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
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
                pausedCount: pausedCountTowardLimit,
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

    func startNewSession(
        ticket: Ticket,
        now: Date,
        startedFrom: RideStartOrigin = .other
    ) throws {
        try refusePassengerDriving()
        let estimate = min(max(ticket.estimatedSeconds, 1), Ticket.maxEstimatedSeconds)
        let session = WorkSession(
            startedAt: now,
            estimatedSecondsAtStart: estimate,
            ticket: ticket,
            boardedDeviceID: deviceIdentity.id
        )
        session.startedFrom = startedFrom
        modelContext.insert(session)
        applyCheckInSchedule(to: session, title: ticket.title, estimatedSeconds: estimate)
        #if DEBUG
        FocusUIPreview.applyQueuedRide(to: session, now: now)
        #endif
        activeSession = session
        phase = .running
        clearTimetableQuietMessage()
        clearIdleCabin(touch: true, now: now)
        bumpCompanionSync()
        try save()
        // One LA / Alarm at a time — drop the previous paused ride's presentation.
        alarmScheduler.cancelAllExcept(sessionID: session.id)
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now)
        requestCheckInPrompt(for: session, title: ticket.title, estimatedMinutes: estimate / 60)
        consumeArrivalCelebrations()
    }

    func pause(
        now: Date? = nil,
        timetableHeld: Bool = false,
        heldBy: PauseHeldBy? = nil,
        pausedOn: PauseOrigin = .iphone,
        heldByInferred: Bool = false
    ) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard !session.isPaused else {
            phase = .paused
            if timetableHeld {
                session.timetableHeld = true
                timetableQuietMessage = TimetableCopy.quiet
            }
            return
        }

        let heldBy = heldBy ?? (timetableHeld ? .timetable : .user)
        try applyPause(
            session: session,
            now: now,
            timetableHeld: timetableHeld,
            heldBy: heldBy,
            pausedOn: pausedOn,
            heldByInferred: heldByInferred
        )
    }

    func applyPause(
        session: WorkSession,
        now: Date,
        syncAlarm: Bool = true,
        timetableHeld: Bool = false,
        heldBy: PauseHeldBy = .user,
        pausedOn: PauseOrigin = .iphone,
        heldByInferred: Bool = false
    ) throws {
        flushToPaused(
            session,
            now: now,
            heldBy: heldBy,
            pausedOn: pausedOn,
            heldByInferred: heldByInferred
        )
        if pausedOn == .iphone, heldBy == .user, !timetableHeld {
            recordStandingPauseAnswer(on: session, now: now)
        }
        session.timetableHeld = timetableHeld
        if timetableHeld {
            timetableQuietMessage = TimetableCopy.quiet
        } else {
            clearTimetableQuietMessage()
        }
        phase = .paused
        noteCabinActivity(now: now, clearPendingIdle: true)
        bumpCompanionSync()
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
    func parkRunningSessionForSwitch(_ session: WorkSession, now: Date) throws {
        flushToPaused(session, now: now, heldBy: .rideSwitch, pausedOn: .iphone, heldByInferred: false)
        session.timetableHeld = false
        liveActivityManager.end()
        alarmScheduler.cancel(sessionID: session.id)
        try save()
    }

    func flushToPaused(
        _ session: WorkSession,
        now: Date,
        heldBy: PauseHeldBy,
        pausedOn: PauseOrigin,
        heldByInferred: Bool
    ) {
        session.closeActiveSegment(at: now)
        session.pausedAt = now
        beginPauseRecord(
            on: session,
            now: now,
            heldBy: heldBy,
            pausedOn: pausedOn,
            heldByInferred: heldByInferred
        )
        session.pendingCheckIn = nil
        session.awayDueAt = nil
        overtimeNotifier.cancel(sessionID: session.id)
        checkInNotifier.cancel(sessionID: session.id)
        cancelAwayFireTask()
    }

    func beginPauseRecord(
        on session: WorkSession,
        now: Date,
        heldBy: PauseHeldBy,
        pausedOn: PauseOrigin,
        heldByInferred: Bool
    ) {
        if session.pauses.contains(where: { $0.endedAt == nil }) { return }
        let record = SessionPause(startedAt: now, session: session)
        record.heldBy = heldBy
        record.pausedOn = pausedOn
        record.heldByInferred = heldByInferred
        modelContext.insert(record)
    }

    func endOpenPauseRecord(on session: WorkSession, now: Date) {
        for pause in session.pauses where pause.endedAt == nil {
            pause.endedAt = now
        }
    }

    /// StandBy / system AlarmKit pause → mirror into the open session (no AlarmKit echo).
    /// A Live Activity 停車 already queued for this ride is the user's pause, not the alarm.
    func pauseFromAlarmKit(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        if isLiveActivityPausePending(sessionID: session.id) {
            try pauseFromLiveActivity(now: now)
            return
        }
        try applyPause(session: session, now: now, syncAlarm: false, heldBy: .alarm, pausedOn: .iphone)
    }

    /// Live Activity 停車. Does not echo AlarmKit; the intent may already have paused it.
    func pauseFromLiveActivity(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        try applyPause(session: session, now: now, syncAlarm: false, heldBy: .user, pausedOn: .iphone)
    }

    private func isLiveActivityPausePending(sessionID: UUID) -> Bool {
        guard let pending = FocusPendingActionStore.peek() else { return false }
        return pending.kind == .pause && pending.sessionID == sessionID
    }

    /// StandBy dismiss / cancel of the end bell — keep the ride running, do not reschedule.
    func suppressEndBell(sessionID: UUID) {
        suppressedEndBellSessionIDs.insert(sessionID)
        alarmScheduler.cancel(sessionID: sessionID)
    }

    func resume(now: Date? = nil) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard session.isPaused else {
            throw SessionError.notPaused
        }

        reopenPausedSession(session, now: now)
        try save()
        alarmScheduler.cancelAllExcept(sessionID: session.id)
        let resumedAlarm = isAlarmKitEndBellActive && alarmScheduler.resume(sessionID: session.id)
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now, endBell: resumedAlarm ? .skip : .schedule)
        consumeArrivalCelebrations()
    }

    /// StandBy / system AlarmKit resume → mirror into the open session (no AlarmKit echo).
    func resumeFromAlarmKit(now: Date? = nil) throws {
        let now = now ?? clock.now
        if passengerChrome.locksDriving || fetchOpenPassengerRide() != nil { return }
        guard let session = activeSession, session.isOpen, session.isPaused else { return }
        reopenPausedSession(session, now: now)
        try save()
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now, endBell: .skip)
        consumeArrivalCelebrations()
    }

    func reopenPausedSession(_ session: WorkSession, now: Date) {
        endOpenPauseRecord(on: session, now: now)
        session.pausedAt = nil
        session.segmentStartedAt = now
        session.timetableHeld = false
        phase = .running
        clearTimetableQuietMessage()
        noteCabinActivity(now: now, clearPendingIdle: true)
        bumpCompanionSync()
    }

    /// UI の二度押しをまとめる。意図した連続延長（秒が違う）は妨げない。
    private static let extendDoubleTapWindow: TimeInterval = 1

    /// 過去の延長記録を作る試験用。本番 UI からは呼ばない。
    func extend(
        by seconds: TimeInterval,
        reason: String? = nil,
        now: Date? = nil,
        nudgeID: String? = nil
    ) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard !session.isPaused else {
            throw SessionError.notRunning
        }
        guard seconds > 0 else { return }

        let added = Int(seconds.rounded())
        if let nudgeID {
            let key = nudgeID.lowercased()
            if session.checkInAnswers.contains(where: {
                $0.nudgeID?.lowercased() == key
                    && $0.answer == .willExtend
                    && $0.addSeconds == added
            }) {
                return
            }
        } else if let recent = session.extensions.max(by: { $0.createdAt < $1.createdAt }),
                  recent.addedSeconds == added,
                  now.timeIntervalSince(recent.createdAt) < Self.extendDoubleTapWindow {
            return
        }
        let working = nudgeWorkingSeconds(for: session, now: now)
        session.currentBudgetSeconds = session.activeBudgetSeconds + added
        noteCabinActivity(now: now, clearPendingIdle: true)
        bumpCompanionSync()
        let record = SessionExtension(
            addedSeconds: added,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: now,
            workingSeconds: working,
            session: session
        )
        modelContext.insert(record)
        fillWillExtendStamp(on: session, addSeconds: added)
        suppressedEndBellSessionIDs.remove(session.id)
        try save()
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now)
    }

    func arrive(resolution: OvertimeResolution? = nil, now: Date? = nil) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        session.preArrivalIdleSeconds = preArrivalIdleSeconds(at: now)
        if let resolution {
            session.overtimeResolution = resolution
        }
        try close(session: session, outcome: .arrived, closureKind: .arrived, now: now)
        enqueueArrivalMomentIfNeeded(session)
    }

    func partialDisembark(now: Date? = nil) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        try close(session: session, outcome: .partialDisembark, closureKind: .partialDisembark, now: now)
    }

    func abandon(now: Date? = nil) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        try close(session: session, outcome: .abandoned, closureKind: .abandoned, now: now)
    }

    func partialDisembark(session: WorkSession, now: Date? = nil) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
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
}
