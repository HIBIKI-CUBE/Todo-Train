//
//  SessionManager+ServiceDay.swift
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
        day.lastCabinActivityAt = now
        modelContext.insert(day)
        activeServiceDay = day
        needsServiceDayEndPrompt = false
        try save()
        overtimeNotifier.requestAuthorizationIfNeeded()
        checkInNotifier.requestAuthorizationIfNeeded()
        alarmScheduler.requestAuthorizationIfNeeded()
        reconcile(now: now)
        bumpCompanionSync()
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
        cancelIdleWatch()
        alarmScheduler.cancelAll()
        try save()
        reconcile(now: now)
        bumpCompanionSync()
        if onTimeService {
            enqueuePunctualityMoment(PunctualityMoment(kind: .onTimeService))
        }
    }
}
