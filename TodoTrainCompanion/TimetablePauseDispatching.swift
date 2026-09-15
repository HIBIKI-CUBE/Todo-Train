import Foundation
import TodoTrainSync

enum TimetablePauseDispatching {
    /// Send pause once per protection boundary. `alreadySent` is that boundary's unix time.
    static func shouldSend(
        now: Int,
        pauseAt: Int?,
        alreadySent: Int?,
        canPause: Bool,
        isSending: Bool
    ) -> Bool {
        guard let pauseAt, now >= pauseAt else { return false }
        guard canPause, !isSending else { return false }
        guard alreadySent != pauseAt else { return false }
        return true
    }
}
