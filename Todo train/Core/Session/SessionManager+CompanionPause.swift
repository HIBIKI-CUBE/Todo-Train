//
//  SessionManager+CompanionPause.swift
//  Todo train
//

import Foundation
import TodoTrainSync

enum CompanionPauseRejection: Error, Equatable {
    case invalidPayload
}

extension SessionManager {
    /// Apply a Mac `pause`. Missing `heldBy` is an older Mac and is the person's pause.
    /// A timetable boundary does not change the reason.
    func applyCompanionPause(_ command: CommandPlaintext, now: Date? = nil) throws {
        let now = now ?? clock.now
        switch PauseReasonResolving.resolve(heldBy: command.heldBy) {
        case .invalidPayload:
            throw CompanionPauseRejection.invalidPayload
        case .explicit(let heldBy):
            try pause(
                now: now,
                timetableHeld: heldBy == .timetable,
                heldBy: heldBy,
                pausedOn: .mac,
                heldByInferred: false
            )
        case .inferred(let heldBy):
            try pause(
                now: now,
                timetableHeld: heldBy == .timetable,
                heldBy: heldBy,
                pausedOn: .mac,
                heldByInferred: true
            )
        }
    }
}
