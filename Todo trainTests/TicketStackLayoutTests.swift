//
//  TicketStackLayoutTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TicketStackLayoutTests {
    @Test func offsets_putsFrontBelowPeeks() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let offsets = TicketStackLayout.offsets(
            orderedIDs: [a, b, c],
            frontID: b,
            ticketHeight: 200,
            peekStep: 40,
            maxPeeks: 8
        )
        #expect(offsets[a] == 0)
        #expect(offsets[c] == 40)
        #expect(offsets[b] == 80)
    }

    @Test func totalHeight_includesBoardBarAndPeeks() {
        let h = TicketStackLayout.totalHeight(
            orderedCount: 3,
            ticketHeight: 200,
            boardBarHeight: 48,
            peekStep: 42,
            maxPeeks: 8
        )
        #expect(abs(h - CGFloat(200 + 48 + 42 * 2)) < 0.01)
    }

    @Test func bringToFront_reordersVisually() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        #expect(TicketStackLayout.orderByBringingToFront(orderedIDs: [a, b, c], tapped: c) == [c, a, b])
    }
}
