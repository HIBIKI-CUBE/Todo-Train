//
//  SessionManager+DeviceSideEffects.swift
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
    func ownsDeviceSideEffects(_ session: WorkSession) -> Bool {
        guard let boarded = session.boardedDeviceID else { return true }
        return boarded == deviceIdentity.id
    }

    /// Refresh or tear down device-local effects after launch / remote change.
    /// Does not collapse duplicate sessions (that stays in `recoverOnLaunch`).
    func refreshOwnedDeviceSideEffects(now: Date, pendingKind: FocusPendingActionKind? = nil) {
        guard let session = activeSession, session.isOpen else {
            liveActivityManager.end()
            alarmScheduler.cancelAll()
            refreshIdleCabin(now: now)
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
        let resumedAlarm = pendingKind == .resume && alarmScheduler.hasAlarm(sessionID: session.id)
        if resumedAlarm {
            _ = alarmScheduler.resume(sessionID: session.id)
        }
        refreshRideSideEffects(for: session, now: now, endBell: resumedAlarm ? .skip : .schedule)
    }

    enum EndBellRefresh {
        case schedule
        case skip
    }

    func refreshRideSideEffects(
        for session: WorkSession,
        now: Date,
        endBell: EndBellRefresh = .schedule
    ) {
        refreshOvertimeNotification(for: session, now: now)
        refreshLiveActivity(for: session, now: now)
        if endBell == .schedule {
            refreshEndBell(for: session, now: now)
        }
        refreshProgressCheckInNotifications(for: session, now: now)
    }

    func refreshLiveActivity(for session: WorkSession, now: Date, presentAwayAlert: Bool = false) {
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

    var awayInterruptChannel: AwayInterruptChannel {
        CheckInScheduling.awayInterruptChannel(
            cabinEnabled: settings.cabinAnnouncementsEnabled,
            alarmKitOwnsLiveActivity: isAlarmKitEndBellActive,
            sessionLiveActivityEnabled: liveActivityManager.areActivitiesEnabled
        )
    }

    func fireAwayInterrupt(_ session: WorkSession, now: Date, presentAlert: Bool) {
        cancelAwayFireTask()
        session.awayDueAt = nil
        session.pendingCheckIn = .away
        try? save()
        refreshLiveActivity(for: session, now: now, presentAwayAlert: presentAlert)
    }

    func armAwayFire(at date: Date, sessionID: UUID) {
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

    func cancelAwayFireTask() {
        awayFireTask?.cancel()
        awayFireTask = nil
        endAwayBackgroundTask()
    }

    func endAwayBackgroundTask() {
        #if canImport(UIKit)
        guard awayBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(awayBackgroundTask)
        awayBackgroundTask = .invalid
        #endif
    }

    func publishWidgetSnapshot(at now: Date) {
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

    func refreshEndBell(for session: WorkSession, now: Date) {
        guard ownsDeviceSideEffects(session) else {
            alarmScheduler.cancel(sessionID: session.id)
            return
        }
        guard settings.endBellEnabled else {
            lastScheduledEndBellFireAt = nil
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
        let budgetFire = SessionEndSchedule.fireAt(
            budgetSeconds: session.budgetSecondsAtStart,
            elapsedSeconds: elapsed,
            now: now
        )
        let nextBlockStart = timetableFit(at: now).nextBlock?.startsAt
        let fireAt = [budgetFire, nextBlockStart].compactMap { $0 }.filter { $0 > now }.min()
        guard let fireAt else {
            lastScheduledEndBellFireAt = nil
            alarmScheduler.cancel(sessionID: session.id)
            return
        }
        if let last = lastScheduledEndBellFireAt,
           abs(last.timeIntervalSince(fireAt)) < 0.5,
           alarmScheduler.hasAlarm(sessionID: session.id) {
            return
        }
        lastScheduledEndBellFireAt = fireAt
        let title = session.ticket?.title ?? "切符"
        alarmScheduler.scheduleEndBell(
            sessionID: session.id,
            ticketTitle: title,
            fireAt: fireAt,
            budgetSeconds: session.budgetSecondsAtStart
        )
    }

    func refreshOvertimeNotification(for session: WorkSession, now: Date) {
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
}
