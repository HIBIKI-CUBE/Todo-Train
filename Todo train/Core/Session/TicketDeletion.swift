//
//  TicketDeletion.swift
//  Todo train
//

import Foundation

/// Pure helpers for ticket / session physical deletion guards.
enum TicketDeletion {
    /// History swipe may only remove ended sessions.
    static func canDeleteEndedSession(_ session: WorkSession) -> Bool {
        session.endedAt != nil
    }

    /// After removing `sessionID`, whether the parent ticket has no remaining sessions.
    static func shouldDeleteOrphanTicket(
        remainingSessionIDs: [UUID],
        removing sessionID: UUID
    ) -> Bool {
        remainingSessionIDs.filter { $0 != sessionID }.isEmpty
    }
}
