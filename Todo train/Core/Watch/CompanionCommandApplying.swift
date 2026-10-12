//
//  CompanionCommandApplying.swift
//  Todo train
//

import Foundation
import TodoTrainSync

/// Applies a command to the iPhone store. The relay and the Watch both call this.
@MainActor
enum CompanionCommandApplying {
    static func apply(
        _ command: CommandPlaintext,
        sessionManager: SessionManager
    ) throws -> AckPlaintext {
        if command.op == .issueAndBoard {
            return issueAndBoardAck(command, sessionManager: sessionManager)
        }
        if command.op == .pauseInputReport {
            return sessionManager.applyPauseInputReport(command)
        }
        if command.op == .answer || command.op == .boardReserved || command.op == .presence {
            return sessionManager.applyNudgeCommand(command)
        }
        var decision = RemotePauseEvaluating.evaluate(
            openSessionId: sessionManager.activeSession?.id,
            pausedCount: sessionManager.pausedCountTowardLimit,
            pauseLimit: sessionManager.pauseLimit,
            isPaused: sessionManager.activeSession?.isPaused == true,
            command: command
        )
        if decision.shouldApply {
            switch command.op {
            case .pause:
                do {
                    try sessionManager.applyCompanionPause(command)
                } catch is CompanionPauseRejection {
                    decision = .invalidPayload
                }
            case .resume:
                try sessionManager.resume()
            case .still:
                sessionManager.acknowledgeCabinStill()
            case .issueAndBoard, .answer, .boardReserved, .presence, .pauseInputReport, .unknown:
                break
            }
        }
        return RemotePauseEvaluating.ack(decision: decision, commandId: command.id)
    }

    private static func issueAndBoardAck(
        _ command: CommandPlaintext,
        sessionManager: SessionManager
    ) -> AckPlaintext {
        let openSessionId: UUID? = {
            guard let session = sessionManager.activeSession,
                  session.isOpen,
                  sessionManager.phase != .idle
            else { return nil }
            return session.id
        }()
        let decision = IssueAndBoardEvaluating.evaluate(
            serviceActive: sessionManager.activeServiceDay?.isOpen == true,
            openSessionId: openSessionId,
            command: command
        )
        switch decision {
        case .board:
            do {
                try sessionManager.issueAndBoard(
                    title: command.title ?? "",
                    estimatedSeconds: command.estimatedSeconds ?? 0
                )
                return IssueAndBoardEvaluating.ack(decision: .board, commandId: command.id)
            } catch let error as SessionError {
                return AckPlaintext(cmdId: command.id, ok: false, error: wireError(for: error))
            } catch {
                return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
            }
        case .noActiveService, .sessionMismatch, .invalidPayload:
            return IssueAndBoardEvaluating.ack(decision: decision, commandId: command.id)
        }
    }

    /// Passenger lock and a stale service day have no dedicated wire code.
    /// Both refuse boarding, so the sender sees `noActiveService` instead of a silent drop.
    private static func wireError(for error: SessionError) -> WireError {
        switch error {
        case .noActiveService, .serviceDayNeedsEnd, .passengerAboard:
            .noActiveService
        case .pauseLimitReached:
            .pauseLimitReached
        default:
            .invalidPayload
        }
    }
}
