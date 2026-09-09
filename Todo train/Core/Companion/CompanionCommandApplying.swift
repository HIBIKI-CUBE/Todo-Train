import Foundation
import TodoTrainSync

enum CompanionCommandApplying {
    /// Remote pause uses the package decision. Local `SessionManager.pause` runs only on `.apply`.
    static func shouldCallPause(_ decision: RemotePauseDecision) -> Bool {
        decision == .apply
    }
}
