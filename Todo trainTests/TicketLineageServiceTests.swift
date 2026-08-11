//
//  TicketLineageServiceTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct TicketLineageServiceTests {
    @Test func issueTransferTickets_createsChildrenAndLineage() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let parent = Ticket(title: "親", estimatedSeconds: 1800)
        context.insert(parent)
        try context.save()

        try TicketLineageService.issueTransferTickets(
            from: parent,
            drafts: [
                .init(title: "子A", estimatedSeconds: 900),
                .init(title: "子B", estimatedSeconds: 600),
            ],
            modelContext: context,
            fromSessionID: UUID()
        )

        let children = try context.fetch(FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.closedAt == nil && $0.title != "親" }
        ))
        #expect(children.count == 2)

        let lineages = try context.fetch(FetchDescriptor<TaskLineage>())
        #expect(lineages.count == 2)
        #expect(lineages.allSatisfy { $0.kind == .split })
        #expect(lineages.allSatisfy { $0.parent?.id == parent.id })
    }
}
