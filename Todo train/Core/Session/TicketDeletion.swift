//
//  TicketDeletion.swift
//  Todo train
//

import Foundation

/// Pure helpers for ticket / session physical deletion guards and footer copy.
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

    enum RideState: Equatable {
        case unused
        case idle
        case paused
        case running
    }

    static func displayTitle(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func rideState(
        hasEndedSessions: Bool,
        isPaused: Bool,
        isRunning: Bool
    ) -> RideState {
        if isRunning { return .running }
        if isPaused { return .paused }
        if hasEndedSessions { return .idle }
        return .unused
    }

    static func rideState(for ticket: Ticket) -> RideState {
        rideState(
            hasEndedSessions: ticket.sessions.contains { $0.endedAt != nil },
            isPaused: ticket.sessions.contains(where: \.isPaused),
            isRunning: ticket.sessions.contains { $0.isOpen && !$0.isPaused }
        )
    }

    static func ticketDeleteFooter(ride: RideState) -> String {
        switch ride {
        case .unused:
            "削除したあと、しばらく取り消せます。"
        case .idle:
            "関連する乗車記録も削除されます。しばらく取り消せます。"
        case .paused:
            "停車中の切符と履歴を削除します。しばらく取り消せます。"
        case .running:
            "フォーカスが閉じます。しばらく取り消せます。"
        }
    }

    static func tagDeleteFooter(ticketCount: Int) -> String {
        ticketCount <= 0
            ? "削除したあと、しばらく取り消せます。"
            : "\(ticketCount) 枚の切符から外れます。しばらく取り消せます。"
    }
}
