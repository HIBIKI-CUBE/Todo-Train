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
        if command.op == .reestimate {
            return reestimateAck(command, sessionManager: sessionManager)
        }
        if command.op == .undoReestimate {
            return undoReestimateAck(command, sessionManager: sessionManager)
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
            case .issueAndBoard, .answer, .boardReserved, .presence, .pauseInputReport, .reestimate, .undoReestimate, .unknown:
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

    /// Records a reestimate by calling the existing commit. Does not add a rule of its own.
    private static func reestimateAck(
        _ command: CommandPlaintext,
        sessionManager: SessionManager
    ) -> AckPlaintext {
        guard let mode = ReestimateMode(command.mode),
              let trigger = ReestimateTrigger(command.trigger),
              let surface = ReestimateSurface(command.surface),
              let input = ReestimateInput(command.input),
              let promptId = command.promptId
        else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
        guard let remaining = command.committedRemainingSeconds else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
        guard let sessionId = command.sessionId else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .noActiveService)
        }
        guard let session = sessionManager.activeSession, session.isOpen, sessionManager.phase != .idle else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .noActiveService)
        }
        guard session.id == sessionId else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .sessionMismatch)
        }
        sessionManager.presentReestimate(trigger: trigger, surface: surface, input: input)
        do {
            try sessionManager.commitReestimate(
                mode: mode,
                progressAnswer: command.progressAnswer,
                committedRemainingSeconds: remaining,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false,
                promptId: promptId
            )
        } catch let error as SessionError {
            sessionManager.dismissReestimate()
            return AckPlaintext(cmdId: command.id, ok: false, error: wireError(for: error))
        } catch {
            sessionManager.dismissReestimate()
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
        return AckPlaintext(cmdId: command.id, ok: true)
    }

    /// Undoes the latest reestimate that is still in effect. A miss uses an existing ack error.
    private static func undoReestimateAck(
        _ command: CommandPlaintext,
        sessionManager: SessionManager
    ) -> AckPlaintext {
        guard let sessionId = command.sessionId else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .noActiveService)
        }
        guard let session = sessionManager.activeSession, session.isOpen, sessionManager.phase != .idle else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .noActiveService)
        }
        guard session.id == sessionId else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .sessionMismatch)
        }
        guard let event = session.reestimateEvents.last(where: { $0.undoneAt == nil }) else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
        do {
            try sessionManager.undoReestimate(eventID: event.id)
        } catch {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
        let undone = sessionManager.activeSession?.reestimateEvents.first { $0.id == event.id }?.undoneAt != nil
        guard undone else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
        return AckPlaintext(cmdId: command.id, ok: true)
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

extension ReestimateMode {
    init?(_ wire: WireReestimateMode?) {
        switch wire {
        case .progress: self = .progress
        case .minutesOnly: self = .minutesOnly
        case .positionReport: self = .positionReport
        case .unknown, .none: return nil
        }
    }
}

extension ReestimateTrigger {
    init?(_ wire: WireReestimateTrigger?) {
        switch wire {
        case .checkIn: self = .checkIn
        case .planEnd: self = .planEnd
        case .manual: self = .manual
        case .unknown, .none: return nil
        }
    }
}

extension ReestimateSurface {
    init?(_ wire: WireReestimateSurface?) {
        switch wire {
        case .iphonePortrait: self = .iphonePortrait
        case .iphoneLandscape: self = .iphoneLandscape
        case .macPip: self = .macPip
        case .unknown, .none: return nil
        }
    }
}

extension ReestimateInput {
    init?(_ wire: WireReestimateInput?) {
        switch wire {
        case .touch: self = .touch
        case .click: self = .click
        case .keyboard: self = .keyboard
        case .trackpadScroll: self = .trackpadScroll
        case .unknown, .none: return nil
        }
    }
}
