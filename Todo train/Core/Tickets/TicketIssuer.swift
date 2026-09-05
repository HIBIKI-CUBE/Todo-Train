//
//  TicketIssuer.swift
//  Todo train
//
//  Shared insert-at-end path for Quick Add and App Intents.
//

import Foundation
import SwiftData

enum TicketIssuer {
    static func resolveMinutes(
        requested: Int?,
        sessions: [WorkSession],
        lastIssued: Int?
    ) -> Int {
        if let requested {
            return AppSettings.clampEstimateMinutes(requested)
        }
        if let suggestion = EstimateHeuristic.suggestion(
            from: EstimateHeuristic.arrivedSamples(from: sessions, matchingAnyTagIDs: nil)
        ) {
            return suggestion.minutes
        }
        if let lastIssued {
            return AppSettings.clampEstimateMinutes(lastIssued)
        }
        return EstimateHeuristic.defaultHighlightMinutes
    }

    @discardableResult
    static func issue(
        title: String,
        minutes: Int,
        into context: ModelContext
    ) throws -> Ticket {
        let minutes = AppSettings.clampEstimateMinutes(minutes)
        let descriptor = FetchDescriptor<Ticket>(sortBy: [SortDescriptor(\.sortOrder)])
        let all = (try? context.fetch(descriptor)) ?? []
        let open = all.filter(\.isOpen)
        var orderedIDs = open.map(\.id)
        let insertAt = TicketSortOrdering.insertionIndex(
            openIDsOrdered: orderedIDs,
            position: .end
        )
        let ticket = Ticket(
            title: title,
            estimatedSeconds: minutes * 60,
            sortOrder: insertAt
        )
        context.insert(ticket)
        orderedIDs.insert(ticket.id, at: insertAt)
        let orders = TicketSortOrdering.normalizedOrders(forOrderedIDs: orderedIDs)
        for existing in open {
            if let order = orders[existing.id] {
                existing.sortOrder = order
            }
        }
        ticket.sortOrder = orders[ticket.id] ?? insertAt
        try context.save()
        return ticket
    }
}
