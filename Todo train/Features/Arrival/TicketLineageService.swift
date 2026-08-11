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
        fromSessionID: UUID? = nil
    ) throws {
        let meaningful = drafts
            .map { Draft(title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), estimatedSeconds: $0.estimatedSeconds) }
            .filter { !$0.title.isEmpty }
        guard !meaningful.isEmpty else { return }

        let kind: LineageKind = meaningful.count == 1 ? .continuation : .split
        var nextOrder = nextSortOrder(in: modelContext)

        for draft in meaningful {
            let child = Ticket(
                title: draft.title,
                estimatedSeconds: min(max(draft.estimatedSeconds, 1), Ticket.maxEstimatedSeconds),
                sortOrder: nextOrder
            )
            nextOrder += 1
            modelContext.insert(child)

            let lineage = TaskLineage(
                kind: kind,
                parent: parent,
                child: child,
                fromSessionID: fromSessionID,
                aiGenerated: false
            )
            modelContext.insert(lineage)
        }

        try modelContext.save()
    }

    @MainActor
    private static func nextSortOrder(in modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.closedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let maxOrder = (try? modelContext.fetch(descriptor).first?.sortOrder) ?? -1
        return maxOrder + 1
    }
}
