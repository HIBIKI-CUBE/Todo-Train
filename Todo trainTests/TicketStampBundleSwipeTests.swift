//
//  TicketStampBundleSwipeTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

@Suite("Ticket stamp bundle swipe")
struct TicketStampBundleSwipeTests {
    private let bundleThreshold = 32.0
    private let bundleFlick = 900.0

    @Test func slowSwipeRightMovesToOlder() {
        let steps = TicketStampBundleSwipe.steps(
            translation: 40,
            velocity: 100,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == -1)
    }

    @Test func flickRightMovesToOlder() {
        let steps = TicketStampBundleSwipe.steps(
            translation: 10,
            velocity: 1500,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == -1)
    }

    @Test func slowSwipeLeftMovesToNewer() {
        let steps = TicketStampBundleSwipe.steps(
            translation: -40,
            velocity: -100,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == 1)
    }

    @Test func flickLeftMovesToNewer() {
        let steps = TicketStampBundleSwipe.steps(
            translation: -10,
            velocity: -1500,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == 1)
    }

    @Test func shortMoveDoesNotAdvance() {
        let steps = TicketStampBundleSwipe.steps(
            translation: 20,
            velocity: 300,
            threshold: bundleThreshold,
            flickVelocity: bundleFlick
        )
        #expect(steps == 0)
    }

    @Test func exactThresholdDoesNotAdvance() {
        let steps = TicketStampBundleSwipe.steps(
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
            let steps = TicketStampBundleSwipe.steps(
                translation: sample.0,
                velocity: sample.1,
                threshold: 40,
                flickVelocity: 1200
            )
            #expect(steps == sample.2)
        }
    }

    @Test func shuttleRateIsDeadZonedSignedAndCapped() {
        for distance in [0.0, 10, 20, -10, -20] {
            #expect(TicketStampBundleSwipe.shuttleCardsPerSecond(distance: distance) == 0)
        }

        let mid = TicketStampBundleSwipe.shuttleCardsPerSecond(distance: 80)
        #expect(abs(mid - (-6)) < 0.0001)
        let midLeft = TicketStampBundleSwipe.shuttleCardsPerSecond(distance: -80)
        #expect(abs(midLeft - 6) < 0.0001)

        #expect(TicketStampBundleSwipe.shuttleCardsPerSecond(distance: 140) == -12)
        #expect(TicketStampBundleSwipe.shuttleCardsPerSecond(distance: -140) == 12)
        #expect(TicketStampBundleSwipe.shuttleCardsPerSecond(distance: 500) == -12)
        #expect(TicketStampBundleSwipe.shuttleCardsPerSecond(distance: -500) == 12)

        let near = abs(TicketStampBundleSwipe.shuttleCardsPerSecond(distance: 40))
        let farther = abs(TicketStampBundleSwipe.shuttleCardsPerSecond(distance: 80))
        let full = abs(TicketStampBundleSwipe.shuttleCardsPerSecond(distance: 140))
        #expect(near < farther)
        #expect(farther < full)
        #expect(full == 12)

        #expect(TicketStampBundleSwipe.shuttleSuppressesPerCardHaptics(cardsPerSecond: -6) == false)
        #expect(TicketStampBundleSwipe.shuttleSuppressesPerCardHaptics(cardsPerSecond: 8) == true)
        #expect(TicketStampBundleSwipe.shuttleSuppressesPerCardHaptics(cardsPerSecond: -12) == true)
    }

    @Test func shuttleAdvanceCarriesFractions() {
        let half = TicketStampBundleSwipe.shuttleAdvance(rate: -12, elapsed: 0.5, carry: 0)
        #expect(half.steps == -6)
        #expect(abs(half.carry) < 0.0001)

        let fraction = TicketStampBundleSwipe.shuttleAdvance(rate: 2, elapsed: 0.4, carry: 0.3)
        #expect(fraction.steps == 1)
        #expect(abs(fraction.carry - 0.1) < 0.0001)

        let held = TicketStampBundleSwipe.shuttleAdvance(rate: 0, elapsed: 1, carry: 0.4)
        #expect(held.steps == 0)
        #expect(abs(held.carry - 0.4) < 0.0001)
    }
}
