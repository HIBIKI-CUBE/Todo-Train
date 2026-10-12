import AppKit
import UserNotifications
import TodoTrainSync

@MainActor
final class CompanionCabinNotifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let identifier = "todotrain.cabin.idle"
    nonisolated static let categoryIdentifier = "todotrain.cabin.idle"
    nonisolated static let stillAction = "todotrain.checkin.still"

    var onStill: (() -> Void)?
    private let center = UNUserNotificationCenter.current()
    private var delivered = false
    private var armedFire: [String: Int] = [:]

    func configure() {
        let still = UNNotificationAction(
            identifier: Self.stillAction,
            title: CabinCopy.still,
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [still],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sync(interrupt: CabinInterrupt) {
        if interrupt.showsNotification, interrupt.kind == .idle {
            deliver(prompt: interrupt.prompt ?? CabinCopy.idle)
        } else {
            removeIdle()
        }
    }

    func apply(_ requests: [MacOffscreenRequest]) {
        let ids = Set(requests.map(\.identifier))
        let stale = Set(armedFire.keys).subtracting(ids)
        if !stale.isEmpty {
            let list = Array(stale)
            center.removePendingNotificationRequests(withIdentifiers: list)
            center.removeDeliveredNotifications(withIdentifiers: list)
            for id in stale { armedFire.removeValue(forKey: id) }
        }
        for request in requests {
            let fire = Int(request.fireAt.timeIntervalSince1970)
            if armedFire[request.identifier] == fire { continue }
            armedFire[request.identifier] = fire
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            if request.identifier.hasPrefix("todotrain.offscreen.idle") {
                content.categoryIdentifier = Self.categoryIdentifier
            }
            let interval = request.fireAt.timeIntervalSinceNow
            let trigger: UNNotificationTrigger? = interval > 1
                ? UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                : nil
            center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            center.add(
                UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
            )
        }
    }

    func remove() {
        delivered = false
        let ids = Array(Set(armedFire.keys).union([Self.identifier]))
        armedFire.removeAll()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func removeIdle() {
        delivered = false
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    private func deliver(prompt: String) {
        guard !delivered else { return }
        delivered = true
        let content = UNMutableNotificationContent()
        content.title = prompt
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let isStill = action == Self.stillAction || action == UNNotificationDefaultActionIdentifier
        guard isStill else { return }
        await MainActor.run {
            onStill?()
        }
    }
}
