//
//  ArriveHandoff.swift
//  Todo train
//
//  Live Activity arrive either lands immediately, or only opens the overtime
//  3-choice. Once that choice is on screen the queue must be cleared, or a
//  later running phase will arrive without a new tap.
//

import Foundation

enum ArriveHandoffDecision: Equatable, Sendable {
    /// Wrong session, or overtime before Focus is up.
    case leaveQueued
    /// Focus is showing the overtime 3-choice. Clear the handoff; do not arrive.
    case consumeOnly
    /// Not overtime. Arrive, then consume only if that mutation succeeds.
    case performArrive
}

enum ArriveHandoff {
    static func decision(
        sessionMatches: Bool,
        phase: SessionPhase,
        focusIsPresented: Bool
    ) -> ArriveHandoffDecision {
        guard sessionMatches else { return .leaveQueued }
        if phase == .overtime {
            return focusIsPresented ? .consumeOnly : .leaveQueued
        }
        return .performArrive
    }

    /// The queued arrive belonged to the overtime 3-choice. Phase has moved on
    /// while Focus was up, so applying it now would arrive a ride the person
    /// already chose to extend (or otherwise leave overtime).
    static func shouldDropOnLeavingOvertime(
        kind: FocusPendingActionKind,
        sessionMatches: Bool,
        focusWasPresented: Bool
    ) -> Bool {
        kind == .arrive && sessionMatches && focusWasPresented
    }
}
