//
//  SessionManager+IdleCabin.swift
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
    func noteCabinActivity(now: Date? = nil, clearPendingIdle: Bool = true) {
        let now = now ?? clock.now
        guard let day = activeServiceDay ?? fetchOpenServiceDay(), day.isOpen else { return }
        if clearPendingIdle, day.pendingCabin == .idle {
            day.pendingCabin = nil
        }
        day.lastCabinActivityAt = now
        cancelIdleWatch()
        checkInNotifier.cancelIdle(serviceDayID: day.id)
        idleLocalNotificationArmed = false
        try? save()
        refreshIdleCabin(now: now)
    }

    func hasOpenRide() -> Bool {
        if let session = activeSession, session.isOpen { return true }
        if fetchRunningSession() != nil { return true }
        return !openPausedSessions().isEmpty
    }

    func clearIdleCabin(touch: Bool, now: Date) {
        guard let day = activeServiceDay ?? fetchOpenServiceDay() else {
            cancelIdleWatch()
            return
        }
        if day.pendingCabin == .idle {
            day.pendingCabin = nil
        }
        cancelIdleWatch()
        checkInNotifier.cancelIdle(serviceDayID: day.id)
        idleLocalNotificationArmed = false
        if touch {
            day.lastCabinActivityAt = now
        }
        try? save()
    }

    func consumeIdleCabinStill(now: Date) {
        guard let day = activeServiceDay ?? fetchOpenServiceDay(), day.isOpen else { return }
        let activity = day.lastCabinActivityAt ?? day.startedAt
        let elapsed = now.timeIntervalSince(activity)
        let due = CabinIdleScheduling.isDue(
            firedCount: day.cabinIdleFiredCount,
            elapsedSinceActivity: elapsed,
            hasPending: false,
            seed: day.id
        )
        guard day.pendingCabin == .idle || due else { return }
        day.pendingCabin = nil
        day.cabinIdleFiredCount += 1
        day.lastCabinActivityAt = now
        cancelIdleWatch()
        checkInNotifier.cancelIdle(serviceDayID: day.id)
        idleLocalNotificationArmed = false
        bumpCompanionSync()
        try? save()
        refreshIdleCabin(now: now)
    }

    func refreshIdleCabin(now: Date) {
        guard let day = activeServiceDay ?? fetchOpenServiceDay(), day.isOpen else {
            cancelIdleWatch()
            idleLocalNotificationArmed = false
            return
        }
        if hasOpenRide() {
            if day.pendingCabin == .idle {
                day.pendingCabin = nil
                try? save()
            }
            cancelIdleWatch()
            checkInNotifier.cancelIdle(serviceDayID: day.id)
            idleLocalNotificationArmed = false
            return
        }
        guard settings.cabinAnnouncementsEnabled else {
            if day.pendingCabin == .idle {
                day.pendingCabin = nil
                try? save()
            }
            cancelIdleWatch()
            checkInNotifier.cancelIdle(serviceDayID: day.id)
            idleLocalNotificationArmed = false
            return
        }
        if day.lastCabinActivityAt == nil {
            day.lastCabinActivityAt = day.startedAt
        }
        let activity = day.lastCabinActivityAt ?? day.startedAt
        let elapsed = now.timeIntervalSince(activity)

        if day.pendingCabin == .idle {
            armIdleLocalNotification(serviceDayID: day.id, fireAt: now.addingTimeInterval(1))
            return
        }

        if CabinIdleScheduling.isDue(
            firedCount: day.cabinIdleFiredCount,
            elapsedSinceActivity: elapsed,
            hasPending: false,
            seed: day.id
        ) {
            day.pendingCabin = .idle
            bumpCompanionSync()
            try? save()
            armIdleLocalNotification(serviceDayID: day.id, fireAt: now.addingTimeInterval(1))
            return
        }

        if let fireAt = CabinIdleScheduling.wallFireAt(
            firedCount: day.cabinIdleFiredCount,
            elapsedSinceActivity: elapsed,
            seed: day.id,
            now: now
        ) {
            checkInNotifier.scheduleIdle(
                serviceDayID: day.id,
                body: CabinCopy.idle,
                fireAt: fireAt
            )
            idleLocalNotificationArmed = true
            armIdleWatch(at: fireAt, serviceDayID: day.id)
        } else {
            cancelIdleWatch()
            checkInNotifier.cancelIdle(serviceDayID: day.id)
            idleLocalNotificationArmed = false
        }
    }

    func armIdleLocalNotification(serviceDayID: UUID, fireAt: Date) {
        guard !idleLocalNotificationArmed else { return }
        checkInNotifier.scheduleIdle(
            serviceDayID: serviceDayID,
            body: CabinCopy.idle,
            fireAt: fireAt
        )
        idleLocalNotificationArmed = true
    }

    func armIdleWatch(at date: Date, serviceDayID: UUID) {
        cancelIdleWatch()
        guard clock is SystemSessionClock else { return }
        idleWatchTask = Task { @MainActor [weak self] in
            let delay = date.timeIntervalSince(self?.clock.now ?? Date())
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.activeServiceDay?.id == serviceDayID else { return }
            self.reconcile()
        }
    }

    func cancelIdleWatch() {
        idleWatchTask?.cancel()
        idleWatchTask = nil
    }
}
