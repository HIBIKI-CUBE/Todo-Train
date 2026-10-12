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
    /// Apply a Mac `pause`. Missing `heldBy` is an older Mac and is inferred.
    /// Arrival is this iPhone's clock, not `command.at`.
    func applyCompanionPause(_ command: CommandPlaintext, now: Date? = nil) throws {
        let now = now ?? clock.now
        let boundary = activeSession.flatMap { session -> Int? in
            guard let date = openTimetableProtectionBoundary(for: session.id) else { return nil }
            return Int(date.timeIntervalSince1970)
        }
        switch PauseReasonResolving.resolve(
            heldBy: command.heldBy,
            arrivedAt: Int(now.timeIntervalSince1970),
            protectionBoundary: boundary
        ) {
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
