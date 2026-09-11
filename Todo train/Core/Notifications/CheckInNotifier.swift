//
//  CheckInNotifier.swift
//  Todo train
//
//  Time Sensitive local notifications for 車内放送 when the app is backgrounded.
//  AlarmKit is not used (end bell owns that channel).
//

import Foundation
import UserNotifications

@MainActor
protocol CheckInNotifying: AnyObject {
    func requestAuthorizationIfNeeded()
    func scheduleProgress(
        sessionID: UUID,
        index: Int,
        ticketTitle: String,
        body: String,
        fireAt: Date
    )
    func scheduleAway(sessionID: UUID, ticketTitle: String, body: String, fireAt: Date)
    func cancel(sessionID: UUID)
    func cancelAll()
}

@MainActor
final class NoOpCheckInNotifier: CheckInNotifying {
    func requestAuthorizationIfNeeded() {}
    func scheduleProgress(
        sessionID: UUID,
        index: Int,
        ticketTitle: String,
        body: String,
        fireAt: Date
    ) {}
    func scheduleAway(sessionID: UUID, ticketTitle: String, body: String, fireAt: Date) {}
    func cancel(sessionID: UUID) {}
    func cancelAll() {}
}

@MainActor
final class InMemoryCheckInNotifier: CheckInNotifying {
    private(set) var progress: [(sessionID: UUID, index: Int, fireAt: Date, body: String)] = []
    private(set) var away: [(sessionID: UUID, fireAt: Date, body: String)] = []

    func requestAuthorizationIfNeeded() {}

    func scheduleProgress(
        sessionID: UUID,
        index: Int,
        ticketTitle: String,
        body: String,
        fireAt: Date
    ) {
        progress.removeAll { $0.sessionID == sessionID && $0.index == index }
        progress.append((sessionID, index, fireAt, body))
    }

    func scheduleAway(sessionID: UUID, ticketTitle: String, body: String, fireAt: Date) {
        away.removeAll { $0.sessionID == sessionID }
        away.append((sessionID, fireAt, body))
    }

    func cancel(sessionID: UUID) {
        progress.removeAll { $0.sessionID == sessionID }
        away.removeAll { $0.sessionID == sessionID }
    }

    func cancelAll() {
        progress.removeAll()
        away.removeAll()
    }
}

enum CheckInNotification {
    static let categoryIdentifier = "todotrain.checkin"
    static let awayCategoryIdentifier = "todotrain.checkin.away"
    static let pauseAction = "todotrain.checkin.pause"
    static let stillOnItAction = "todotrain.checkin.still"

    static func progressIdentifier(sessionID: UUID, index: Int) -> String {
        "checkin.progress.\(sessionID.uuidString).\(index)"
    }

    static func awayIdentifier(sessionID: UUID) -> String {
        "checkin.away.\(sessionID.uuidString)"
    }

    static func isCheckIn(_ identifier: String) -> Bool {
        identifier.hasPrefix("checkin.")
    }

    static func isAway(_ identifier: String) -> Bool {
        identifier.hasPrefix("checkin.away.")
    }
}

@MainActor
final class CheckInNotifier: CheckInNotifying {
    static let shared = CheckInNotifier()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func configure() {
        let pause = UNNotificationAction(
            identifier: CheckInNotification.pauseAction,
            title: "停車",
            options: []
        )
        let still = UNNotificationAction(
            identifier: CheckInNotification.stillOnItAction,
            title: "まだやってる",
            options: []
        )
        let progress = UNNotificationCategory(
            identifier: CheckInNotification.categoryIdentifier,
            actions: [pause, still],
            intentIdentifiers: [],
            options: []
        )
        let away = UNNotificationCategory(
            identifier: CheckInNotification.awayCategoryIdentifier,
            actions: [pause],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([progress, away])
    }

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func scheduleProgress(
        sessionID: UUID,
        index: Int,
        ticketTitle: String,
        body: String,
        fireAt: Date
    ) {
        let identifier = CheckInNotification.progressIdentifier(sessionID: sessionID, index: index)
        enqueue(
            identifier: identifier,
            title: "Todo train",
            body: body,
            fireAt: fireAt,
            categoryIdentifier: CheckInNotification.categoryIdentifier
        )
    }

    func scheduleAway(sessionID: UUID, ticketTitle: String, body: String, fireAt: Date) {
        let identifier = CheckInNotification.awayIdentifier(sessionID: sessionID)
        enqueue(
            identifier: identifier,
            title: CheckInCopy.away,
            body: ticketTitle,
            fireAt: fireAt,
            categoryIdentifier: CheckInNotification.awayCategoryIdentifier
        )
    }

    func cancel(sessionID: UUID) {
        var identifiers = [CheckInNotification.awayIdentifier(sessionID: sessionID)]
        for index in 0..<4 {
            identifiers.append(CheckInNotification.progressIdentifier(sessionID: sessionID, index: index))
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAll() {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter(CheckInNotification.isCheckIn)
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func enqueue(
        identifier: String,
        title: String,
        body: String,
        fireAt: Date,
        categoryIdentifier: String
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = categoryIdentifier

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
}
