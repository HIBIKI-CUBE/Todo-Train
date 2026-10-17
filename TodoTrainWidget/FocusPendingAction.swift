//
//  FocusPendingAction.swift
//  Shared by app + TodoTrainWidget — App Group handoff from LA Intents.
//

import AppIntents
import Foundation

nonisolated enum FocusPendingActionKind: String, Codable, Sendable {
    case arrive
    case extend
    case pause
    case resume
    case still
}

nonisolated struct FocusPendingAction: Codable, Equatable, Sendable {
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

struct SessionStillIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "続行"
    static var description = IntentDescription("走行中の問いを続行にします。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID")
    var sessionID: String

    init() { sessionID = "" }

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else { return .result() }
        await MainActor.run {
            if let pauser = SessionPauseRuntime.pauser {
                pauser.continueRide(sessionID: id)
            } else {
                FocusPendingActionStore.enqueue(
                    FocusPendingAction(kind: .still, sessionID: id, createdAt: .now)
                )
            }
        }
        return .result()
    }
}

@MainActor
protocol SessionRidePausing: AnyObject {
    func pauseRide(sessionID: UUID)
    func continueRide(sessionID: UUID)
}

@MainActor
enum SessionPauseRuntime {
    static var pauser: (any SessionRidePausing)?
}

nonisolated enum FocusPendingActionStore {
    static let suiteKey = "focus.pendingAction"
    static let didEnqueueNotification = Notification.Name("TodoTrain.focusPendingActionEnqueued")

    /// Tests inject a private suite; production always uses the App Group.
    nonisolated(unsafe) static var defaultsOverride: UserDefaults?

    static var defaults: UserDefaults? {
        if let defaultsOverride { return defaultsOverride }
        return UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)
    }

    static func enqueue(_ action: FocusPendingAction) {
        guard let data = try? JSONEncoder().encode(action) else { return }
        defaults?.set(data, forKey: suiteKey)
        // In-process Live Activity intents do not change scenePhase.
        // Hop to main so SwiftUI observers are not updated mid-enqueue.
        let post = {
            NotificationCenter.default.post(name: Self.didEnqueueNotification, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    static func peek() -> FocusPendingAction? {
        guard let data = defaults?.data(forKey: suiteKey) else { return nil }
        return try? JSONDecoder().decode(FocusPendingAction.self, from: data)
    }

    /// Returns and clears the pending action (if any).
    static func consume() -> FocusPendingAction? {
        guard let action = peek() else { return nil }
        guard consumeIfMatches(action) else { return nil }
        return action
    }

    /// Clears the slot only when it still holds `expected`.
    /// A widget write during save must not be deleted with the action we already applied.
    @discardableResult
    static func consumeIfMatches(_ expected: FocusPendingAction) -> Bool {
        guard peek() == expected else { return false }
        defaults?.removeObject(forKey: suiteKey)
        return true
    }

    /// Drop stale LA arrive/extend handoffs before a fresh departure from the arrival ceremony.
    static func discardArriveAndExtendHandoffs() {
        guard let pending = peek() else { return }
        switch pending.kind {
        case .arrive, .extend:
            defaults?.removeObject(forKey: suiteKey)
        case .pause, .resume, .still:
            break
        }
    }
}
