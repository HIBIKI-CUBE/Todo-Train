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
            remove()
        }
    }

    func remove() {
        delivered = false
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    private func deliver(prompt: String) {
        guard !delivered else { return }
        delivered = true
        let content = UNMutableNotificationContent()
        content.title = prompt
        content.body = CabinCopy.still
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
