//
//  TicketReissue.swift
//  Todo train
//

import Foundation

enum TicketReissue {
    /// Copies a closed ticket into a new open ticket for today's Hub inbox.
    static func makeTodayCopy(from ticket: Ticket, sortOrder: Int) -> Ticket {
        let copy = Ticket(
            title: ticket.title,
            estimatedSeconds: ticket.estimatedSeconds,
            sortOrder: sortOrder
        )
        copy.tags = ticket.tags
        copy.dueDate = ticket.dueDate
        return copy
    }
}
