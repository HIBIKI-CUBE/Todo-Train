//
//  SessionPauseIntent.swift
//  Shared by app + TodoTrainWidget (Session Live Activity 停車).
//

import AppIntents
import Foundation

struct SessionPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停車"
    static var description = IntentDescription("走行中の切符を停車します。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID")
    var sessionID: String

    init() {
        sessionID = ""
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else { return .result() }
        await MainActor.run {
            if let pauser = SessionPauseRuntime.pauser {
                pauser.pauseRide(sessionID: id)
            } else {
                FocusPendingActionStore.enqueue(
                    FocusPendingAction(kind: .pause, sessionID: id, createdAt: .now)
                )
            }
        }
        return .result()
    }
}
