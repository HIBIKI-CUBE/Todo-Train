//
//  TicketSortOrderingTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TicketSortOrderingTests {
    @Test func insertionIndex_endIsAppend() {
        let ids = [UUID(), UUID()]
        #expect(TicketSortOrdering.insertionIndex(openIDsOrdered: ids, position: .end) == 2)
        #expect(TicketSortOrdering.insertionIndex(openIDsOrdered: [], position: .end) == 0)
    }

    @Test func insertionIndex_startIsZero() {
        let ids = [UUID(), UUID()]
        #expect(TicketSortOrdering.insertionIndex(openIDsOrdered: ids, position: .start) == 0)
    }

    @Test func insertionIndex_afterKnownTicket() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let ids = [a, b, c]
        #expect(TicketSortOrdering.insertionIndex(openIDsOrdered: ids, position: .after(a)) == 1)
        #expect(TicketSortOrdering.insertionIndex(openIDsOrdered: ids, position: .after(c)) == 3)
    }

    @Test func insertionIndex_afterUnknownFallsBackToEnd() {
        let ids = [UUID()]
        #expect(TicketSortOrdering.insertionIndex(openIDsOrdered: ids, position: .after(UUID())) == 1)
    }

    @Test func normalizedOrders_areContiguous() {
        let a = UUID()
        let b = UUID()
        let orders = TicketSortOrdering.normalizedOrders(forOrderedIDs: [a, b])
        #expect(orders[a] == 0)
        #expect(orders[b] == 1)
    }
}
