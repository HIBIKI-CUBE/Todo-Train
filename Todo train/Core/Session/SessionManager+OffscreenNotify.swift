//
//  SessionManager+OffscreenNotify.swift
//  Todo train
//
//  Safety-net notifications fire only when neither screen is showing them.
//

import Foundation
import TodoTrainSync

extension SessionManager {
    var offscreenScreens: OffscreenScreens {
        let paired = suppressProgressLocalNotifications
        let known = paired ? macPresenceKnown : true
        let riding = activeSession?.isOpen == true && phase != .idle
        return OffscreenScreens(
            sceneActive: iphoneSceneActive,
            focusVisible: iphoneFocusVisible,
            riding: riding,
            hubVisible: iphoneHubVisible,
            macPipVisible: known && macPipVisible,
            macAttending: known && macAttending,
            macKnown: known
        )
    }

    func offscreenDelivery(kind: OffscreenKind, turn: Int, now: Date) -> OffscreenDelivery {
        OffscreenNotify.delivery(
            kind: kind,
            screens: offscreenScreens,
            turn: turn,
            now: now,
            calendar: calendar
        )
    }

    func iphonePosts(_ kind: OffscreenKind, turn: Int, now: Date) -> Bool {
        offscreenDelivery(kind: kind, turn: turn, now: now) == .iphone
    }

    func offscreenAssignment(now: Date) -> (on: NotifyOn, turn: Int?, fireAt: Int?) {
        if activeSession?.isOpen == true, phase != .idle {
            let delivery = offscreenDelivery(kind: .overtime, turn: 0, now: now)
            let fire = activeSession?.awayDueAt.map { Int($0.timeIntervalSince1970) }
            return (notifyOn(delivery), delivery == .none ? nil : 0, delivery == .mac ? fire : nil)
        }
        let fired = activeServiceDay?.cabinIdleFiredCount ?? 0
        let delivery = offscreenDelivery(kind: .idle, turn: fired, now: now)
        return (notifyOn(delivery), delivery == .none ? nil : fired, delivery == .mac ? idleFireUnix(now: now) : nil)
    }

    func refreshOffscreenNotifications(now: Date? = nil) {
        let now = now ?? clock.now
        if let session = activeSession, session.isOpen {
            refreshOvertimeNotification(for: session, now: now)
            refreshProgressCheckInNotifications(for: session, now: now)
        }
        refreshIdleCabin(now: now)
        publishOffscreenAssignment(now: now)
    }

    func noteIphoneFocus(_ visible: Bool) {
        let changed = iphoneFocusVisible != visible
        iphoneFocusVisible = visible
        guard changed else { return }
        refreshOffscreenNotifications()
    }

    func noteMacPresenceUnreachable() {
        guard suppressProgressLocalNotifications, macPresenceKnown else { return }
        macPresenceKnown = false
        refreshOffscreenNotifications()
    }

    func shouldPresentOffscreenNotification(_ identifier: String) -> Bool {
        guard let kind = offscreenKind(identifier) else { return false }
        if kind == .progress { return false }
        if offscreenScreens.macKnown && offscreenScreens.macPipVisible { return false }
        if OffscreenNotify.iphoneOnScreen(kind: kind, screens: offscreenScreens) { return false }
        return ReminderDay.allows(clock.now, calendar: calendar)
    }

    private func notifyOn(_ delivery: OffscreenDelivery) -> NotifyOn {
        switch delivery {
        case .iphone: .iphone
        case .mac: .mac
        case .none: .none
        }
    }

    private func idleFireUnix(now: Date) -> Int? {
        guard let day = activeServiceDay ?? fetchOpenServiceDay(), day.isOpen else { return nil }
        if day.pendingCabin == .idle {
            return Int(now.timeIntervalSince1970)
        }
        let activity = day.lastCabinActivityAt ?? day.startedAt
        let elapsed = now.timeIntervalSince(activity)
        return CabinIdleScheduling.wallFireAt(
            firedCount: day.cabinIdleFiredCount,
            elapsedSinceActivity: elapsed,
            seed: day.id,
            now: now
        ).map { Int($0.timeIntervalSince1970) }
    }

    func publishOffscreenAssignment(now: Date) {
        let next = offscreenAssignment(now: now)
        guard next.on != lastNotifyOn || next.turn != lastNotifyTurn || next.fireAt != lastNotifyFireAt else { return }
        lastNotifyOn = next.on
        lastNotifyTurn = next.turn
        lastNotifyFireAt = next.fireAt
        bumpCompanionSync()
    }

    private func offscreenKind(_ identifier: String) -> OffscreenKind? {
        if identifier.hasPrefix("overtime.") { return .overtime }
        if CheckInNotification.isAway(identifier) { return .away }
        if CheckInNotification.isIdle(identifier) { return .idle }
        if CheckInNotification.isProgress(identifier) { return .progress }
        return nil
    }
}
