import Foundation

public enum RemotePauseDecision: Equatable, Sendable {
    case apply
    case sessionMismatch
    case pauseLimitReached
    case noActiveService

    public var wireError: WireError? {
        switch self {
        case .apply: nil
        case .sessionMismatch: .sessionMismatch
        case .pauseLimitReached: .pauseLimitReached
        case .noActiveService: .noActiveService
        }
    }
}

/// Pure function: does not import SessionManager.
///
/// `pausedCount` is the number of already-paused tickets (WIP cap). Remote pause
/// of a running ride is refused at the cap so Mac can surface `pauseLimitReached`.
public enum RemotePauseEvaluating {
    public static func evaluate(
        openSessionId: UUID?,
        pausedCount: Int,
        pauseLimit: Int,
        command: CommandPlaintext
    ) -> RemotePauseDecision {
        guard command.op == .pause else { return .noActiveService }
        guard let openSessionId else { return .noActiveService }
        guard command.sessionId == openSessionId else { return .sessionMismatch }
        if pausedCount >= pauseLimit { return .pauseLimitReached }
        return .apply
    }

    public static func ack(
        decision: RemotePauseDecision,
        commandId: UUID
    ) -> AckPlaintext {
        switch decision {
        case .apply:
            AckPlaintext(cmdId: commandId, ok: true)
        case .sessionMismatch, .pauseLimitReached, .noActiveService:
            AckPlaintext(cmdId: commandId, ok: false, error: decision.wireError)
        }
    }
}
