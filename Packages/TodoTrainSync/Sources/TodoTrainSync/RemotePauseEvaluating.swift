import Foundation

public enum RemotePauseDecision: Equatable, Sendable {
    case apply
    case sessionMismatch
    case pauseLimitReached
    case noActiveService
    case notPaused

    public var wireError: WireError? {
        switch self {
        case .apply: nil
        case .sessionMismatch: .sessionMismatch
        case .pauseLimitReached: .pauseLimitReached
        case .noActiveService: .noActiveService
        case .notPaused: .notPaused
        }
    }
}

/// Pure function: does not import SessionManager.
///
/// `pausedCount` is the number of already-paused tickets (WIP cap). Remote pause
/// of a running ride is refused at the cap so Mac can surface `pauseLimitReached`.
/// Resume ignores the cap; it needs the open session to already be paused.
public enum RemotePauseEvaluating {
    public static func evaluate(
        openSessionId: UUID?,
        pausedCount: Int,
        pauseLimit: Int,
        isPaused: Bool = false,
        command: CommandPlaintext
    ) -> RemotePauseDecision {
        switch command.op {
        case .pause, .resume:
            guard let commandSession = command.sessionId else { return .noActiveService }
            guard let openSessionId else { return .noActiveService }
            guard commandSession == openSessionId else { return .sessionMismatch }
            if command.op == .pause {
                if pausedCount >= pauseLimit { return .pauseLimitReached }
                return .apply
            }
            if !isPaused { return .notPaused }
            return .apply
        case .still:
            if let commandSession = command.sessionId {
                guard let openSessionId else { return .noActiveService }
                guard commandSession == openSessionId else { return .sessionMismatch }
            }
            return .apply
        }
    }

    public static func ack(
        decision: RemotePauseDecision,
        commandId: UUID
    ) -> AckPlaintext {
        switch decision {
        case .apply:
            AckPlaintext(cmdId: commandId, ok: true)
        case .sessionMismatch, .pauseLimitReached, .noActiveService, .notPaused:
            AckPlaintext(cmdId: commandId, ok: false, error: decision.wireError)
        }
    }
}
