//
//  TicketStackLayoutTests.swift
//  Todo trainTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Todo_train

struct TicketStackLayoutTests {
    @Test func offsets_includeEveryTicket() {
        let ids = (0..<12).map { _ in UUID() }
        let offsets = TicketStackLayout.offsets(orderedIDs: ids, peekStep: 10)
        #expect(offsets.count == 12)
        #expect(offsets[ids[0]] == 0)
        #expect(offsets[ids[11]] == 110)
    }

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

    @Test func liftOffset_risesInPlace() {
        let rest = TicketStackLayout.liftOffset(isLifted: false, rise: 22)
        let held = TicketStackLayout.liftOffset(isLifted: true, rise: 22)
        #expect(rest == .zero)
        #expect(held == CGSize(width: 0, height: -22))
    }

    @Test func holdOffset_restsAboveSlot_andTracksDownOneToOne() {
        let rest = TicketStackLayout.holdOffset(restRise: 22, translation: .zero)
        #expect(rest == CGSize(width: 0, height: -22))

        let intoSlot = TicketStackLayout.holdOffset(
            restRise: 22,
            translation: CGSize(width: 0, height: 22)
        )
        #expect(abs(intoSlot.height) < 0.01)
        #expect(abs(intoSlot.width) < 0.01)
    }

    @Test func holdOffset_rubberBandsPastSlot_andResistsUp() {
        let overflow = TicketStackLayout.holdOffset(
            restRise: 22,
            translation: CGSize(width: 0, height: 42),
            downwardOverflowFactor: 0.22
        )
        #expect(abs(overflow.height - 4.4) < 0.01)

        let up = TicketStackLayout.holdOffset(
            restRise: 22,
            translation: CGSize(width: 0, height: -20),
            upwardFactor: 0.32
        )
        #expect(abs(up.height - (-22 + -6.4)) < 0.01)
    }

    @Test func holdScale_tracksSeat() {
        let lifted = TicketStackLayout.holdScale(holdY: -22, restRise: 22, liftedScale: 1.025)
        let seated = TicketStackLayout.holdScale(holdY: 0, restRise: 22, liftedScale: 1.025)
        #expect(abs(lifted - 1.025) < 0.0001)
        #expect(abs(seated - 1) < 0.0001)
    }

    @Test func shouldPutBack_whenNearSlotOrFlicked() {
        #expect(
            TicketStackLayout.shouldPutBack(
                holdY: -4,
                translation: CGSize(width: 0, height: 18),
                predictedEnd: .zero,
                restRise: 22
            )
        )
        #expect(
            !TicketStackLayout.shouldPutBack(
                holdY: -20,
                translation: CGSize(width: 0, height: 4),
                predictedEnd: .zero,
                restRise: 22
            )
        )
        #expect(
            TicketStackLayout.shouldPutBack(
                holdY: -20,
                translation: CGSize(width: 0, height: 4),
                predictedEnd: CGSize(width: 0, height: 110),
                restRise: 22
            )
        )
    }

    @Test func holdOffset_tracksHorizontalOneToOne() {
        let right = TicketStackLayout.holdOffset(
            restRise: 22,
            translation: CGSize(width: 40, height: 0)
        )
        #expect(abs(right.width - 40) < 0.01)
        #expect(abs(right.height - (-22)) < 0.01)

        let left = TicketStackLayout.holdOffset(
            restRise: 22,
            translation: CGSize(width: -50, height: 0)
        )
        #expect(abs(left.width - (-50)) < 0.01)
    }

    @Test func holdRelease_onlyCommittedRightBoards() {
        #expect(
            TicketStackLayout.holdRelease(
                hold: CGSize(width: 160, height: -18),
                translation: CGSize(width: 160, height: 4),
                predictedEnd: CGSize(width: 200, height: 4),
                canBoard: true
            ) == .board
        )
        #expect(
            TicketStackLayout.holdRelease(
                hold: CGSize(width: 160, height: -18),
                translation: CGSize(width: 160, height: 4),
                predictedEnd: CGSize(width: 200, height: 4),
                canBoard: false
            ) == .putBack
        )
        #expect(
            TicketStackLayout.holdRelease(
                hold: CGSize(width: 90, height: -18),
                translation: CGSize(width: 90, height: 4),
                predictedEnd: CGSize(width: 140, height: 4),
                canBoard: true
            ) == .putBack
        )
        #expect(
            TicketStackLayout.holdRelease(
                hold: CGSize(width: -80, height: -16),
                translation: CGSize(width: -80, height: 6),
                predictedEnd: CGSize(width: -130, height: 6),
                canBoard: true
            ) == .putBack
        )
        #expect(
            TicketStackLayout.holdRelease(
                hold: CGSize(width: 8, height: -200),
                translation: CGSize(width: 8, height: -6),
                predictedEnd: CGSize(width: 10, height: -8),
                canBoard: true
            ) == .putBack
        )
    }
}
