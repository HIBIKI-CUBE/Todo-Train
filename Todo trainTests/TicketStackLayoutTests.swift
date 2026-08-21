//
//  TicketStackLayoutTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TicketStackLayoutTests {
    @Test func offsets_followSortOrderTopToBottom() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let offsets = TicketStackLayout.offsets(
            orderedIDs: [a, b, c],
            peekStep: 104,
            maxPeeks: 8
        )
        #expect(offsets[a] == 0)
        #expect(offsets[b] == 104)
        #expect(offsets[c] == 208)
    }

    @Test func totalHeight_frontShowsFullFace() {
        let h = TicketStackLayout.totalHeight(
            orderedCount: 3,
            faceHeight: 220,
            peekStep: 104,
            maxPeeks: 8
        )
        #expect(abs(h - CGFloat(220 + 104 * 2)) < 0.01)
    }

    @Test func tiltDegrees_frontIsFlattest() {
        let back = TicketStackLayout.tiltDegrees(index: 0, count: 3, near: 1, far: 7)
        let mid = TicketStackLayout.tiltDegrees(index: 1, count: 3, near: 1, far: 7)
        let front = TicketStackLayout.tiltDegrees(index: 2, count: 3, near: 1, far: 7)
        #expect(back == 7)
        #expect(abs(mid - 4) < 0.01)
        #expect(front == 1)
    }
}
