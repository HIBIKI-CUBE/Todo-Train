//
//  FocusPendingAction.swift
//  Shared by app + TodoTrainWidget — App Group handoff from LA Intents.
//

import AppIntents
import Foundation

enum FocusPendingActionKind: String, Codable, Sendable {
    case arrive
    case extend
    case pause
    case resume
}

struct FocusPendingAction: Codable, Equatable, Sendable {
    var kind: FocusPendingActionKind
    var sessionID: UUID
    var createdAt: Date
}

struct SessionResumeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "再乗車"
    static var description = IntentDescription("停車中のカウントダウンを再開します。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Session ID")
    var sessionID: String

    init() { sessionID = "" }

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else { return .result() }
        FocusPendingActionStore.enqueue(
            FocusPendingAction(kind: .resume, sessionID: id, createdAt: .now)
        )
        return .result()
    }
}

@MainActor
protocol SessionRidePausing: AnyObject {
    func pauseRide(sessionID: UUID)
}

@MainActor
enum SessionPauseRuntime {
    static var pauser: (any SessionRidePausing)?
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
