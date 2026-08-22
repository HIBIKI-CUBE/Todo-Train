//
//  TicketStackLayoutTests.swift
//  Todo trainTests
//

import CoreGraphics
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

    @Test func liftOffset_movesSlotToCanvasCenterAboveConsole() {
        let stack = CGRect(x: 0, y: 200, width: 390, height: 400)
        let slot = TicketStackLayout.slotCenter(
            stackFrame: stack,
            horizontalInset: 16,
            faceWidth: 358,
            faceHeight: 242,
            slotTopY: 104
        )
        let dest = TicketStackLayout.liftDestination(
            stackFrame: stack,
            canvasSize: CGSize(width: 390, height: 800),
            consoleReserve: 72
        )
        let lift = TicketStackLayout.liftOffset(from: slot, to: dest)
        #expect(abs(dest.x - 195) < 0.01)
        #expect(abs(dest.y - 364) < 0.01)
        #expect(abs(slot.x + lift.width - dest.x) < 0.01)
        #expect(abs(slot.y + lift.height - dest.y) < 0.01)
    }
}
