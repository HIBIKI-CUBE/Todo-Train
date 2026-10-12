//
//  SessionManagerInventoryTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionManagerInventoryTests {
    @Test func issueInventoryTicket_writesThroughManagerContext() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        let issued = try manager.issueInventoryTicket(title: "  案内  ", minutes: 25)

        #expect(issued.ticket.title == "案内")
        #expect(issued.minutes == 25)
        #expect(issued.ticket.estimatedSeconds == 25 * 60)
        #expect(manager.settings.lastIssuedEstimateMinutes == 25)

        let fetched = try context.fetch(FetchDescriptor<Ticket>())
        #expect(fetched.contains { $0.id == issued.ticket.id })
    }

    @Test func issueInventoryTicket_resolvesMinutesWhenOmitted() throws {
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness()
        manager.settings.lastIssuedEstimateMinutes = 40
        let issued = try manager.issueInventoryTicket(title: "続き")
        #expect(issued.minutes == 40)
    }

    @Test func issueInventoryTicket_rejectsEmptyTitle() throws {
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness()
        #expect(throws: SessionError.emptyTicketTitle) {
            try manager.issueInventoryTicket(title: "   ")
        }
    }

    @Test func issueInventoryTicket_appendsAfterExistingOpenTicket() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        _ = try manager.issueInventoryTicket(title: "先", minutes: 10)
        let second = try manager.issueInventoryTicket(title: "後", minutes: 15)
        let open = try context.fetch(FetchDescriptor<Ticket>()).filter(\.isOpen)
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(open.map(\.title) == ["先", "後"])
        #expect(second.ticket.sortOrder == open.last?.sortOrder)
    }
}
