//
//  TicketLineageService.swift
//  Todo train
//

import Foundation
import SwiftData

enum TicketLineageService {
    struct Draft: Equatable {
        var title: String
        var estimatedSeconds: Int
    }

    @MainActor
    static func issueTransferTickets(
        from parent: Ticket,
        drafts: [Draft],
        modelContext: ModelContext,
        fromSessionID: UUID? = nil,
        insertionPosition: TicketInsertionPosition = .end
    ) throws {
        let meaningful = drafts
            .map { Draft(title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), estimatedSeconds: $0.estimatedSeconds) }
            .filter { !$0.title.isEmpty }
        guard !meaningful.isEmpty else { return }

        let kind: LineageKind = meaningful.count == 1 ? .continuation : .split

        let openDescriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.closedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let openTickets = (try? modelContext.fetch(openDescriptor)) ?? []
        var orderedIDs = openTickets.map(\.id)
        var insertAt = TicketSortOrdering.insertionIndex(
            openIDsOrdered: orderedIDs,
            position: insertionPosition
        )

        var created: [Ticket] = []
        for draft in meaningful {
            let child = Ticket(
                title: draft.title,
                estimatedSeconds: min(max(draft.estimatedSeconds, 1), Ticket.maxEstimatedSeconds),
                sortOrder: insertAt
            )
            modelContext.insert(child)
            created.append(child)

            let lineage = TaskLineage(
                kind: kind,
                parent: parent,
                child: child,
                fromSessionID: fromSessionID,
                aiGenerated: false
            )
            modelContext.insert(lineage)

            orderedIDs.insert(child.id, at: insertAt)
            insertAt += 1
        }

        let orders = TicketSortOrdering.normalizedOrders(forOrderedIDs: orderedIDs)
        for ticket in openTickets + created {
            if let order = orders[ticket.id] {
                ticket.sortOrder = order
            }
        }

        try modelContext.save()
    }
}
