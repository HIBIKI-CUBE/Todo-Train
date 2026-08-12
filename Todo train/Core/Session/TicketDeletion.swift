//
//  TicketDeletion.swift
//  Todo train
//

import Foundation

/// Pure helpers for ticket / session physical deletion guards and confirmation copy.
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

    /// How a ticket is currently riding — drives confirmation copy.
    enum RideState: Equatable {
        /// Never boarded (or no sessions left).
        case unused
        /// Closed / has ended sessions, not currently riding.
        case idle
        case paused
        case running
    }

    struct Prompt: Equatable {
        var title: String
        var message: String
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

    static func ticketPrompt(
        title: String,
        ride: RideState,
        hasTransferChildren: Bool = false
    ) -> Prompt {
        let quoted = "「\(displayTitle(title, fallback: "無題の切符"))」"
        let titleText: String
        var message: String
        switch ride {
        case .unused:
            titleText = "この切符を削除しますか？"
            message = "\(quoted)を削除します。"
        case .idle:
            titleText = "切符と履歴を削除しますか？"
            message = "\(quoted)と、関連する乗車記録も削除されます。"
        case .paused:
            titleText = "停車中の切符を削除しますか？"
            message = "\(quoted)は停車中です。切符と履歴を削除します。"
        case .running:
            titleText = "走行中の切符を削除しますか？"
            message = "\(quoted)は走行中です。フォーカスと終了ベルが止まり、切符と履歴も削除されます。"
        }
        if hasTransferChildren {
            message += "乗り継ぎ先の切符は残ります。"
        }
        message += "この操作は取り消せません。"
        return Prompt(title: titleText, message: message)
    }

    static func ticketPrompt(for ticket: Ticket) -> Prompt {
        ticketPrompt(
            title: ticket.title,
            ride: rideState(for: ticket),
            hasTransferChildren: ticket.childLineages.contains { $0.child != nil }
        )
    }

    /// Short Form footer for the ticket-delete section (alert carries the full copy).
    static func ticketDeleteFooter(ride: RideState) -> String {
        switch ride {
        case .unused:
            "Hub からこの切符を取り除きます。"
        case .idle:
            "関連する乗車記録も削除されます。"
        case .paused:
            "停車中のまま、切符と履歴を削除します。"
        case .running:
            "フォーカスが閉じ、切符と履歴も削除されます。"
        }
    }

    static func tagDeleteFooter(ticketCount: Int) -> String {
        ticketCount <= 0
            ? "このタグを取り除きます。切符には影響しません。"
            : "\(ticketCount) 枚の切符から外れます。切符自体は残ります。"
    }

    static func historySessionPrompt(
        ticketTitle: String,
        isLastSession: Bool,
        hasTransferChildren: Bool = false
    ) -> Prompt {
        let quoted = "「\(displayTitle(ticketTitle, fallback: "不明な切符"))」"
        if isLastSession {
            var message = "これが\(quoted)の最後の記録です。履歴と切符の両方を削除します。"
            if hasTransferChildren {
                message += "乗り継ぎ先の切符は残ります。"
            }
            message += "この操作は取り消せません。"
            return Prompt(title: "履歴と切符を削除しますか？", message: message)
        }
        return Prompt(
            title: "この履歴を削除しますか？",
            message: "\(quoted)のこの乗車記録だけを削除します。切符と他の履歴は残ります。"
        )
    }

    static func historySessionPrompt(for session: WorkSession) -> Prompt {
        let ticket = session.ticket
        let remainingIDs = ticket?.sessions.map(\.id) ?? [session.id]
        return historySessionPrompt(
            ticketTitle: ticket?.title ?? "不明な切符",
            isLastSession: shouldDeleteOrphanTicket(
                remainingSessionIDs: remainingIDs,
                removing: session.id
            ),
            hasTransferChildren: ticket?.childLineages.contains { $0.child != nil } ?? false
        )
    }

    static func tagPrompt(name: String, ticketCount: Int) -> Prompt {
        let quoted = "「\(displayTitle(name, fallback: "無題のタグ"))」"
        if ticketCount <= 0 {
            return Prompt(
                title: "このタグを削除しますか？",
                message: "\(quoted)を削除します。切符には影響しません。"
            )
        }
        return Prompt(
            title: "このタグを削除しますか？",
            message: "\(quoted)を削除します。\(ticketCount) 枚の切符からこのタグが外れます。切符自体は残ります。"
        )
    }

    static func tagPrompt(for tag: Tag) -> Prompt {
        tagPrompt(name: tag.name, ticketCount: tag.tickets.count)
    }
}
