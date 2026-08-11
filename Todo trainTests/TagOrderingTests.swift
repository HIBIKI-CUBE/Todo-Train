//
//  TagOrderingTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct TagOrderingTests {
    @Test func normalizeSortOrders_reindexesFromZero() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let a = Tag(name: "A", sortOrder: 5)
        let b = Tag(name: "B", sortOrder: 2)
        let c = Tag(name: "C", sortOrder: 9)
        context.insert(a)
        context.insert(b)
        context.insert(c)

        TagOrdering.normalizeSortOrders([b, a, c])
        #expect(b.sortOrder == 0)
        #expect(a.sortOrder == 1)
        #expect(c.sortOrder == 2)
    }

    @Test func ticket_canAttachMultipleTags() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let work = Tag(name: "仕事", colorHex: "#0091FF", sortOrder: 0)
        let home = Tag(name: "家", colorHex: "#30A46C", sortOrder: 1)
        let ticket = Ticket(title: "請求書", estimatedSeconds: 900)
        context.insert(work)
        context.insert(home)
        context.insert(ticket)

        ticket.tags = [work, home]
        try context.save()

        #expect(ticket.tags.count == 2)
        #expect(ticket.tags.map(\.name).sorted() == ["仕事", "家"].sorted())
        #expect(work.tickets.contains(where: { $0.id == ticket.id }))
    }
}
