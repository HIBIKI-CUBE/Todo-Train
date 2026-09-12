import Foundation
import TodoTrainSync

enum CompanionCommandApplying {
    /// Remote ride cmds use the package decision. Local SessionManager runs only on `.apply`.
    static func shouldCallPause(_ decision: RemotePauseDecision, op: WireOp) -> Bool {
        decision == .apply && op == .pause
    }

    static func shouldCallResume(_ decision: RemotePauseDecision, op: WireOp) -> Bool {
        decision == .apply && op == .resume
    }
}
