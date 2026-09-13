//
//  TicketReissueTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct TicketReissueTests {
    @Test func makeTodayCopy_copiesFieldsWithoutLineage() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let tag = Tag(name: "仕事", colorHex: "#3366FF", sortOrder: 0)
        context.insert(tag)

        let original = Ticket(title: "週次レポート", estimatedSeconds: 23 * 60, sortOrder: 0)
        original.tags = [tag]
        original.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        original.closedAt = .now
        original.closureKind = .arrived
        context.insert(original)
        try context.save()

        let copy = TicketReissue.makeTodayCopy(from: original, sortOrder: 5)

        #expect(copy.title == original.title)
        #expect(copy.estimatedSeconds == original.estimatedSeconds)
        #expect(copy.tags.map(\.id) == original.tags.map(\.id))
        #expect(copy.dueDate == original.dueDate)
        #expect(copy.sortOrder == 5)
        #expect(copy.isOpen)
        #expect(copy.id != original.id)
        #expect(copy.parentLineages.isEmpty)
        #expect(copy.childLineages.isEmpty)
    }
}
