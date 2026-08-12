//
//  FocusPendingAction.swift
//  Shared by app + TodoTrainWidget — App Group handoff from LA Intents.
//

import Foundation

enum FocusPendingActionKind: String, Codable, Sendable {
    case arrive
    case extend
}

struct FocusPendingAction: Codable, Equatable, Sendable {
    var kind: FocusPendingActionKind
    var sessionID: UUID
    var createdAt: Date
}

enum FocusPendingActionStore {
    static let suiteKey = "focus.pendingAction"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)
    }

    static func enqueue(_ action: FocusPendingAction) {
        guard let data = try? JSONEncoder().encode(action) else { return }
        defaults?.set(data, forKey: suiteKey)
    }

    static func peek() -> FocusPendingAction? {
        guard let data = defaults?.data(forKey: suiteKey) else { return nil }
        return try? JSONDecoder().decode(FocusPendingAction.self, from: data)
    }

    /// Returns and clears the pending action (if any).
    static func consume() -> FocusPendingAction? {
        guard let action = peek() else { return nil }
        defaults?.removeObject(forKey: suiteKey)
        return action
    }
}
