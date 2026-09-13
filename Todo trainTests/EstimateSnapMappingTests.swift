//
//  EstimateSnapMappingTests.swift
//  Todo trainTests
//

import CoreGraphics
import Testing
@testable import Todo_train

struct EstimateSnapMappingTests {
    @Test func fraction_mapsLinearly() {
        #expect(EstimateSnapMapping.fraction(minutes: 0) == 0)
        #expect(EstimateSnapMapping.fraction(minutes: 30) == 0.5)
        #expect(EstimateSnapMapping.fraction(minutes: 60) == 1)
        #expect(EstimateSnapMapping.fraction(minutes: 90) == 1)
    }

    @Test func snap_nearestStopPreferringLowerOnTie() {
        #expect(EstimateSnapMapping.snap(rawMinutes: 22) == 20)
        #expect(EstimateSnapMapping.snap(rawMinutes: 27) == 30)
        #expect(EstimateSnapMapping.snap(rawMinutes: 5) == 5)
        #expect(EstimateSnapMapping.snap(rawMinutes: 60) == 60)
        // Midpoint 25 between 20 and 30 → lower wins
        #expect(EstimateSnapMapping.snap(rawMinutes: 25) == 20)
    }

    @Test func snap_fractionMatchesVisualCenter() {
        #expect(EstimateSnapMapping.snap(fraction: 0.5) == 30)
        #expect(EstimateSnapMapping.snap(fraction: 1) == 60)
        #expect(EstimateSnapMapping.snap(fraction: 0) == 5)
    }

    @Test func snap_xWithinWidthMatchesFingerModel() {
        let width: CGFloat = 300
        #expect(EstimateSnapMapping.snap(x: 150, width: width) == 30)
        #expect(EstimateSnapMapping.snap(x: 300, width: width) == 60)
        #expect(EstimateSnapMapping.snap(x: 0, width: width) == 5)
        #expect(EstimateSnapMapping.snap(x: 100, width: width) == 20)
    }

    @Test func rubberBand_identityInsideUnitInterval() {
        #expect(EstimateSnapMapping.rubberBand(0) == 0)
        #expect(EstimateSnapMapping.rubberBand(0.5) == 0.5)
        #expect(EstimateSnapMapping.rubberBand(1) == 1)
    }

    @Test func rubberBand_dampsOutsideUnitInterval() {
        let below = EstimateSnapMapping.rubberBand(-0.5)
        #expect(below < 0)
        #expect(below > -0.5)

        let above = EstimateSnapMapping.rubberBand(1.5)
        #expect(above > 1)
        #expect(above < 1.5)
    }

    @Test func stop_forFingerFraction_usesClampedSnap() {
        #expect(EstimateSnapMapping.stop(forFingerFraction: 0.5) == 30)
        #expect(EstimateSnapMapping.stop(forFingerFraction: -0.2) == 5)
        #expect(EstimateSnapMapping.stop(forFingerFraction: 1.4) == 60)
    }

    @Test func stickyScrub_staysAnchoredBeforeEscape() {
        // 30 → 45 gap: midpoint-ish still sticky
        let midish = (EstimateSnapMapping.fraction(minutes: 30)
                      + EstimateSnapMapping.fraction(minutes: 45)) / 2
        let scrub = EstimateSnapMapping.stickyScrub(
            fingerFraction: midish,
            anchoredMinutes: 30
        )
        #expect(scrub.anchoredMinutes == 30)
        #expect(scrub.didEscape == false)
        #expect(scrub.displayFraction > EstimateSnapMapping.fraction(minutes: 30))
        #expect(scrub.displayFraction < EstimateSnapMapping.fraction(minutes: 45))
    }

    @Test func stickyScrub_escapesPastHysteresis() {
        let from = EstimateSnapMapping.fraction(minutes: 30)
        let to = EstimateSnapMapping.fraction(minutes: 45)
        let gap = to - from
        let past = from + gap * (EstimateSnapMapping.stickyEscapeProgress + 0.05)
        let scrub = EstimateSnapMapping.stickyScrub(
            fingerFraction: past,
            anchoredMinutes: 30
        )
        #expect(scrub.didEscape == true)
        #expect(scrub.anchoredMinutes == 45)
        #expect(scrub.displayFraction == to)
    }

    @Test func stickyScrub_stretchIsLessThanFingerTravel() {
        let from = EstimateSnapMapping.fraction(minutes: 30)
        let to = EstimateSnapMapping.fraction(minutes: 45)
        let gap = to - from
        let finger = from + gap * 0.4
        let scrub = EstimateSnapMapping.stickyScrub(
            fingerFraction: finger,
            anchoredMinutes: 30
        )
        #expect(scrub.didEscape == false)
        #expect(scrub.displayFraction < finger)
        #expect(scrub.displayFraction > from)
    }
}
