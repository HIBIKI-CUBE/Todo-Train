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
            pausedCount: pausedCountTowardLimit,
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

    func startNewSession(ticket: Ticket, now: Date) throws {
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
        clearTimetableQuietMessage()
        clearIdleCabin(touch: true, now: now)
        bumpCompanionSync()
        try save()
        // One LA / Alarm at a time — drop the previous paused ride's presentation.
        alarmScheduler.cancelAllExcept(sessionID: session.id)
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now)
        requestCheckInPrompt(for: session, title: ticket.title, estimatedMinutes: estimate / 60)
    }

    func pause(now: Date? = nil, timetableHeld: Bool = false) throws {
        let now = now ?? clock.now
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

        try applyPause(session: session, now: now, timetableHeld: timetableHeld)
    }

    func applyPause(session: WorkSession, now: Date, syncAlarm: Bool = true, timetableHeld: Bool = false) throws {
        flushToPaused(session, now: now)
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
        flushToPaused(session, now: now)
        session.timetableHeld = false
        liveActivityManager.end()
        alarmScheduler.cancel(sessionID: session.id)
        try save()
    }

    func flushToPaused(_ session: WorkSession, now: Date) {
        session.closeActiveSegment(at: now)
        session.pausedAt = now
        beginPauseRecord(on: session, now: now)
        session.pendingCheckIn = nil
        session.awayDueAt = nil
        overtimeNotifier.cancel(sessionID: session.id)
        checkInNotifier.cancel(sessionID: session.id)
        cancelAwayFireTask()
    }

    func beginPauseRecord(on session: WorkSession, now: Date) {
        if session.pauses.contains(where: { $0.endedAt == nil }) { return }
        let record = SessionPause(startedAt: now, session: session)
        modelContext.insert(record)
    }

    func endOpenPauseRecord(on session: WorkSession, now: Date) {
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

        reopenPausedSession(session, now: now)
        try save()
        alarmScheduler.cancelAllExcept(sessionID: session.id)
        let resumedAlarm = isAlarmKitEndBellActive && alarmScheduler.resume(sessionID: session.id)
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now, endBell: resumedAlarm ? .skip : .schedule)
    }

    /// StandBy / system AlarmKit resume → mirror into the open session (no AlarmKit echo).
    func resumeFromAlarmKit(now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen, session.isPaused else { return }
        reopenPausedSession(session, now: now)
        try save()
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now, endBell: .skip)
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
        noteCabinActivity(now: now, clearPendingIdle: true)
        bumpCompanionSync()
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
        refreshRideSideEffects(for: session, now: now)
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
}
