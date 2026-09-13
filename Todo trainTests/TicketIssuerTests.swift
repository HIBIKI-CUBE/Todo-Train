//
//  TicketIssuerTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct TicketIssuerTests {
    @Test func resolveMinutes_prefersRequestedThenHeuristicThenLast() {
        #expect(
            TicketIssuer.resolveMinutes(requested: 12, sessions: [], lastIssued: 45) == 12
        )
        #expect(
            TicketIssuer.resolveMinutes(requested: nil, sessions: [], lastIssued: 45) == 45
        )
        #expect(
            TicketIssuer.resolveMinutes(requested: nil, sessions: [], lastIssued: nil)
                == EstimateHeuristic.defaultHighlightMinutes
        )
        #expect(
            TicketIssuer.resolveMinutes(requested: 90, sessions: [], lastIssued: nil) == 60
        )
    }

    @Test func issue_appendsOpenTicket() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let first = try TicketIssuer.issue(title: "A", minutes: 10, into: context)
        let second = try TicketIssuer.issue(title: "B", minutes: 20, into: context)
        #expect(first.sortOrder == 0)
        #expect(second.sortOrder == 1)
        #expect(second.estimatedSeconds == 20 * 60)
    }
}
