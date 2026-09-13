import Foundation
import TodoTrainSync

enum OutgoingPauseApplying {
    /// Nil means the same cmd is already in flight — do not resend.
    static func beginSending(cmdId: UUID, current: OutgoingPauseState) -> OutgoingPauseState? {
        if case .sending = current { return nil }
        return .sending(cmdId: cmdId)
    }

    static func applyAck(_ ack: AckPlaintext, current: OutgoingPauseState) -> OutgoingPauseState {
        guard case .sending(let cmdId) = current, ack.cmdId == cmdId else { return current }
        if ack.ok { return .idle }
        return .failed(ack.error ?? .decryptFailed)
    }

    static func nextCommandRev(current: Int) -> Int {
        current + 1
    }
}
