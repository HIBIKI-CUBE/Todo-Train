//
//  TicketUIShim.swift
//  Todo train
//
//  Mars face lives in TodoTrainTicketUI. Ticket / Tag conveniences stay here.
//

@_exported import TodoTrainTicketUI

extension TicketStockColor {
    static func winningColorHex(tags: [Tag]) -> String? {
        winningColorHex(from: tags.map { (sortOrder: $0.sortOrder, colorHex: $0.colorHex) })
    }
}

extension MarsTicketContent {
    init(ticket: Ticket) {
        let tags = ticket.tags.sorted { $0.sortOrder < $1.sortOrder }
        self.init(
            title: ticket.title,
            minutes: max(ticket.estimatedSeconds / 60, 1),
            tagNames: tags.map(\.name),
            colorHex: TicketStockColor.winningColorHex(tags: tags),
            issuedAt: ticket.createdAt,
            serial: MarsTicketContent.makeSerial(from: ticket.createdAt, salt: ticket.id)
        )
    }
}

extension TicketIssueEjectEvent {
    init(ticket: Ticket) {
        self.init(
            ticketID: ticket.id,
            title: ticket.title,
            minutes: max(1, ticket.estimatedSeconds / 60),
            tagNames: ticket.tags
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.name),
            issuedAt: ticket.createdAt
        )
    }
}
