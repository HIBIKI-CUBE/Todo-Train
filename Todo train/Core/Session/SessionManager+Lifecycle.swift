//
//  SessionManager+Lifecycle.swift
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
            refreshIdleCabin(now: now)
            applyTimetableEffects(now: now)
            return
            }
            return reconcile(now: now)
        }

        applyTimetableEffects(now: now)

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
        if crossedIntoOvertime {
            bumpCompanionSync()
        }
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
                stale.closeActiveSegment(at: now)
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

}
