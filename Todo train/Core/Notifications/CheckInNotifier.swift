//
//  CheckInNotifier.swift
//  Todo train
//
//  Time Sensitive local notifications for 車内放送 when the app is backgrounded.
//  AlarmKit is not used (end bell owns that channel).
//

import Foundation
import UserNotifications
import TodoTrainSync

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
    func scheduleIdle(serviceDayID: UUID, body: String, fireAt: Date)
    func scheduleTimetablePause(sessionID: UUID, guardID: UUID, title: String, fireAt: Date)
    func cancel(sessionID: UUID)
    func cancelProgress(sessionID: UUID)
    func cancelIdle(serviceDayID: UUID)
    func cancelTimetable(sessionID: UUID)
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
    func scheduleIdle(serviceDayID: UUID, body: String, fireAt: Date) {}
    func scheduleTimetablePause(sessionID: UUID, guardID: UUID, title: String, fireAt: Date) {}
    func cancel(sessionID: UUID) {}
    func cancelProgress(sessionID: UUID) {}
    func cancelIdle(serviceDayID: UUID) {}
    func cancelTimetable(sessionID: UUID) {}
    func cancelAll() {}
}

@MainActor
final class InMemoryCheckInNotifier: CheckInNotifying {
    private(set) var progress: [(sessionID: UUID, index: Int, fireAt: Date, body: String)] = []
    private(set) var away: [(sessionID: UUID, fireAt: Date, body: String)] = []
    private(set) var idle: [(serviceDayID: UUID, fireAt: Date, body: String)] = []
    private(set) var timetable: [(sessionID: UUID, guardID: UUID, fireAt: Date, title: String)] = []

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

    func scheduleIdle(serviceDayID: UUID, body: String, fireAt: Date) {
        idle.removeAll { $0.serviceDayID == serviceDayID }
        idle.append((serviceDayID, fireAt, body))
    }

    func scheduleTimetablePause(sessionID: UUID, guardID: UUID, title: String, fireAt: Date) {
        timetable.removeAll { $0.sessionID == sessionID }
        timetable.append((sessionID, guardID, fireAt, title))
    }

    func cancel(sessionID: UUID) {
        progress.removeAll { $0.sessionID == sessionID }
        away.removeAll { $0.sessionID == sessionID }
        timetable.removeAll { $0.sessionID == sessionID }
    }

    func cancelProgress(sessionID: UUID) {
        progress.removeAll { $0.sessionID == sessionID }
    }

    func cancelIdle(serviceDayID: UUID) {
        idle.removeAll { $0.serviceDayID == serviceDayID }
    }

    func cancelTimetable(sessionID: UUID) {
        timetable.removeAll { $0.sessionID == sessionID }
    }

    func cancelAll() {
        progress.removeAll()
        away.removeAll()
        idle.removeAll()
        timetable.removeAll()
    }
}

nonisolated enum CheckInNotification {
    static let categoryIdentifier = "todotrain.checkin"
    static let awayCategoryIdentifier = "todotrain.checkin.away"
    static let idleCategoryIdentifier = "todotrain.checkin.idle"
    static let pauseAction = "todotrain.checkin.pause"
    static let stillOnItAction = "todotrain.checkin.still"

    static func progressIdentifier(sessionID: UUID, index: Int) -> String {
        "checkin.progress.\(sessionID.uuidString).\(index)"
    }

    static func awayIdentifier(sessionID: UUID) -> String {
        "checkin.away.\(sessionID.uuidString)"
    }

    static func idleIdentifier(serviceDayID: UUID) -> String {
        "checkin.idle.\(serviceDayID.uuidString)"
    }

    static func isCheckIn(_ identifier: String) -> Bool {
        identifier.hasPrefix("checkin.")
    }

    static func isAway(_ identifier: String) -> Bool {
        identifier.hasPrefix("checkin.away.")
    }

    static func isIdle(_ identifier: String) -> Bool {
        identifier.hasPrefix("checkin.idle.")
    }
}

nonisolated enum TimetableNotification {
    static let categoryIdentifier = "todotrain.timetable"
    static let pauseAction = "todotrain.timetable.pause"

    static func identifier(sessionID: UUID, guardID: UUID) -> String {
        "timetable.pause.\(sessionID.uuidString).\(guardID.uuidString)"
    }

    static func isTimetable(_ identifier: String) -> Bool {
        identifier.hasPrefix("timetable.pause.")
    }

    static func parse(_ identifier: String) -> (sessionID: UUID, guardID: UUID)? {
        let parts = identifier.split(separator: ".")
        guard parts.count == 4, parts[0] == "timetable", parts[1] == "pause" else { return nil }
        guard let sessionID = UUID(uuidString: String(parts[2])),
              let guardID = UUID(uuidString: String(parts[3])) else { return nil }
        return (sessionID, guardID)
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
        let idle = UNNotificationCategory(
            identifier: CheckInNotification.idleCategoryIdentifier,
            actions: [still],
            intentIdentifiers: [],
            options: []
        )
        let timetablePause = UNNotificationAction(
            identifier: TimetableNotification.pauseAction,
            title: TimetableCopy.pause,
            options: []
        )
        let timetable = UNNotificationCategory(
            identifier: TimetableNotification.categoryIdentifier,
            actions: [timetablePause],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([progress, away, idle, timetable])
    }

    func requestAuthorizationIfNeeded() {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
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

    func scheduleIdle(serviceDayID: UUID, body: String, fireAt: Date) {
        let identifier = CheckInNotification.idleIdentifier(serviceDayID: serviceDayID)
        enqueue(
            identifier: identifier,
            title: CabinCopy.idle,
            body: CabinCopy.still,
            fireAt: fireAt,
            categoryIdentifier: CheckInNotification.idleCategoryIdentifier
        )
    }

    func scheduleTimetablePause(sessionID: UUID, guardID: UUID, title: String, fireAt: Date) {
        cancelTimetable(sessionID: sessionID)
        let identifier = TimetableNotification.identifier(sessionID: sessionID, guardID: guardID)
        enqueue(
            identifier: identifier,
            title: TimetableCopy.board,
            body: TimetableCopy.notificationBody(title: title),
            fireAt: fireAt,
            categoryIdentifier: TimetableNotification.categoryIdentifier
        )
    }

    func cancel(sessionID: UUID) {
        var identifiers = [CheckInNotification.awayIdentifier(sessionID: sessionID)]
        for index in 0..<4 {
            identifiers.append(CheckInNotification.progressIdentifier(sessionID: sessionID, index: index))
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        cancelTimetable(sessionID: sessionID)
    }

    func cancelProgress(sessionID: UUID) {
        var identifiers: [String] = []
        for index in 0..<4 {
            identifiers.append(CheckInNotification.progressIdentifier(sessionID: sessionID, index: index))
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelIdle(serviceDayID: UUID) {
        let identifier = CheckInNotification.idleIdentifier(serviceDayID: serviceDayID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelTimetable(sessionID: UUID) {
        let prefix = "timetable.pause.\(sessionID.uuidString)."
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            guard !ids.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
            self.center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func cancelAll() {
        Task {
            let ids = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { CheckInNotification.isCheckIn($0) || TimetableNotification.isTimetable($0) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
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

        let interval = max(fireAt.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
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
