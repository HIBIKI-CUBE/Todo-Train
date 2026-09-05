//
//  OvertimeNotifier.swift
//  Todo train
//

import Foundation
import UserNotifications

@MainActor
protocol OvertimeNotifying: AnyObject {
    func requestAuthorizationIfNeeded()
    func schedule(sessionID: UUID, ticketTitle: String, fireAt: Date)
    func cancel(sessionID: UUID)
    func cancelAll()
}

/// No-op for unit tests.
@MainActor
final class NoOpOvertimeNotifier: OvertimeNotifying {
    func requestAuthorizationIfNeeded() {}
    func schedule(sessionID: UUID, ticketTitle: String, fireAt: Date) {}
    func cancel(sessionID: UUID) {}
    func cancelAll() {}
}

/// Test double that records scheduled overtime notifications.
@MainActor
final class InMemoryOvertimeNotifier: OvertimeNotifying {
    private(set) var scheduledSessionIDs: [UUID] = []
    private(set) var cancelledSessionIDs: [UUID] = []

    func requestAuthorizationIfNeeded() {}

    func schedule(sessionID: UUID, ticketTitle: String, fireAt: Date) {
        scheduledSessionIDs.append(sessionID)
    }

    func cancel(sessionID: UUID) {
        cancelledSessionIDs.append(sessionID)
        scheduledSessionIDs.removeAll { $0 == sessionID }
    }

    func cancelAll() {
        scheduledSessionIDs.removeAll()
    }
}

@MainActor
final class OvertimeNotifier: NSObject, OvertimeNotifying, UNUserNotificationCenterDelegate {
    static let shared = OvertimeNotifier()

    weak var sessionManager: SessionManager?

    private let center: UNUserNotificationCenter
    private var didConfigureDelegate = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func configure() {
        guard !didConfigureDelegate else { return }
        center.delegate = self
        didConfigureDelegate = true
    }

    func requestAuthorizationIfNeeded() {
        configure()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func schedule(sessionID: UUID, ticketTitle: String, fireAt: Date) {
        configure()
        let identifier = OvertimeSchedule.notificationIdentifier(sessionID: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Todo train"
        content.body = "『\(ticketTitle)』の見積もりを過ぎました"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let interval = fireAt.timeIntervalSinceNow
        guard interval > 0 else { return }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(interval, 1),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancel(sessionID: UUID) {
        let identifier = OvertimeSchedule.notificationIdentifier(sessionID: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // Prefer in-app OvertimeOverlay while Focus is foreground; never stack a banner on top.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        await MainActor.run {
            sessionManager?.handleCheckInNotification(identifier: identifier, action: action)
        }
    }
}
