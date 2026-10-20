//
//  TicketStampBundleGestureTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

@Suite("Ticket stamp bundle gesture")
struct TicketStampBundleGestureTests {
    @Test func shortMoveInsideTheSlopIsATap() {
        let kind = TicketStampBundleGesture.classify(dx: 5, dy: 0, duration: 0.1)
        #expect(kind == .tap)
    }

    @Test func shortMoveHeldLongerIsNotATap() {
        let kind = TicketStampBundleGesture.classify(dx: 5, dy: 0, duration: 0.5)
        #expect(kind != .tap)
    }

    @Test func widerMoveIsHorizontal() {
        let kind = TicketStampBundleGesture.classify(dx: 12, dy: 3, duration: 0.2)
        #expect(kind == .horizontal)
    }

    @Test func tallerMoveIsVertical() {
        let kind = TicketStampBundleGesture.classify(dx: 3, dy: 12, duration: 0.2)
        #expect(kind == .vertical)
    }

    @Test func zeroVelocityKeepsTheFocus() {
        let focus = TicketStampBundleGesture.projectedFocus(
            focus: 4,
            velocity: 0,
            travelPerCard: 30,
            count: 12
        )
        #expect(focus == 4)
    }

    @Test func fastFlickMovesSeveralCardsAndStopsAtTheEnd() {
        let flicked = TicketStampBundleGesture.projectedFocus(
            focus: 8,
            velocity: 1800,
            travelPerCard: 30,
            count: 20
        )
        #expect(flicked < 8)
        #expect(8 - flicked >= 3)

        let stopped = TicketStampBundleGesture.projectedFocus(
            focus: 2,
            velocity: 4000,
            travelPerCard: 20,
            count: 10
        )
        #expect(stopped == 0)
    }

    @Test func crossingsCountBothDirections() {
        let forward = TicketStampBundleGesture.crossings(from: 2.4, to: 5.1)
        let backward = TicketStampBundleGesture.crossings(from: 5.1, to: 2.4)
        #expect(forward.count == 3)
        #expect(backward.count == 3)
        #expect(forward == [3, 4, 5])
        #expect(backward == [5, 4, 3])
    }

    private let bundleThreshold = 32.0
    private let bundleFlick = 900.0

    @Test func slowSwipeRightMovesToOlder() {
        let steps = TicketStampBundleGesture.steps(
            translation: 40,
            velocity: 100,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == -1)
    }

    @Test func flickRightMovesToOlder() {
        let steps = TicketStampBundleGesture.steps(
            translation: 10,
            velocity: 1500,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == -1)
    }

    @Test func slowSwipeLeftMovesToNewer() {
        let steps = TicketStampBundleGesture.steps(
            translation: -40,
            velocity: -100,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == 1)
    }

    @Test func flickLeftMovesToNewer() {
        let steps = TicketStampBundleGesture.steps(
            translation: -10,
            velocity: -1500,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == 1)
    }

    @Test func shortMoveDoesNotAdvance() {
        let steps = TicketStampBundleGesture.steps(
            translation: 20,
            velocity: 300,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == 0)
    }

    @Test func exactThresholdDoesNotAdvance() {
        let steps = TicketStampBundleGesture.steps(
            translation: 32,
            velocity: 900,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == 0)
    }

    @Test func viewerScrubMatchesTheSameRule() {
        let samples: [(Double, Double, Int)] = [
            (50, 0, -1),
            (-50, 0, 1),
            (10, 1300, -1),
            (-10, -1300, 1),
            (30, 100, 0),
            (40, 1200, 0),
            (41, 100, -1),
            (-41, -100, 1),
        ]
        for sample in samples {
            let steps = TicketStampBundleGesture.steps(
                translation: sample.0,
                velocity: sample.1,
                threshold: 40,
                flickVelocity: 1200
            )
            #expect(steps == sample.2)
        }
    }
}
