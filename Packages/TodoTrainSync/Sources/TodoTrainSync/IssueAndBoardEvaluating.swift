import Foundation

public enum IssueAndBoardDecision: Equatable, Sendable {
    case board
    case noActiveService
    case sessionMismatch
    case invalidPayload

    public var wireError: WireError? {
        switch self {
        case .board: nil
        case .noActiveService: .noActiveService
        case .sessionMismatch: .sessionMismatch
        case .invalidPayload: .invalidPayload
        }
    }
}

/// Pure gate for `op: issueAndBoard`. Does not issue or board.
public enum IssueAndBoardEvaluating {
    /// 1 minute. Matches the host estimate floor.
    public static let minimumEstimatedSeconds = 60
    /// 60 minutes. `Ticket.maxEstimatedSeconds`.
    public static let maximumEstimatedSeconds = 3_600

    public static func trimmedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isValid(title: String, estimatedSeconds: Int) -> Bool {
        !trimmedTitle(title).isEmpty
            && (minimumEstimatedSeconds...maximumEstimatedSeconds).contains(estimatedSeconds)
    }

    /// `openSessionId` is the ride the next snap would publish. Nil when not riding.
    public static func evaluate(
        serviceActive: Bool,
        openSessionId: UUID?,
        command: CommandPlaintext
    ) -> IssueAndBoardDecision {
        guard command.op == .issueAndBoard else { return .invalidPayload }
        guard serviceActive else { return .noActiveService }
        guard let title = command.title,
              let seconds = command.estimatedSeconds,
              isValid(title: title, estimatedSeconds: seconds)
        else {
            return .invalidPayload
        }
        if let openSessionId {
            guard command.sessionId == openSessionId else { return .sessionMismatch }
        } else if command.sessionId != nil {
            return .sessionMismatch
        }
        return .board
    }

    public static func ack(decision: IssueAndBoardDecision, commandId: UUID) -> AckPlaintext {
        if decision == .board {
            return AckPlaintext(cmdId: commandId, ok: true)
        }
        return AckPlaintext(cmdId: commandId, ok: false, error: decision.wireError)
    }
}
