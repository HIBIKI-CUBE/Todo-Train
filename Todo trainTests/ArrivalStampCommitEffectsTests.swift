//
//  ArrivalStampCommitEffectsTests.swift
//  Todo trainTests
//

import CoreGraphics
import Testing
@testable import Todo_train

@Suite("Arrival stamp commit")
struct ArrivalStampCommitEffectsTests {
    @Test func settledVisuals_onTimeShowsCornerSeal() {
        let settled = ArrivalStampCommitEffects.settledVisuals(punctuality: .onTime)
        #expect(settled.stampImpact == 1)
        #expect(settled.sealImpact == 1)
    }

    @Test func settledVisuals_lateHidesCornerSeal() {
        let settled = ArrivalStampCommitEffects.settledVisuals(punctuality: .late)
        #expect(settled.stampImpact == 1)
        #expect(settled.sealImpact == 0)
    }

    @Test func settledVisuals_earlyHidesCornerSeal() {
        let settled = ArrivalStampCommitEffects.settledVisuals(punctuality: .early)
        #expect(settled.stampImpact == 1)
        #expect(settled.sealImpact == 0)
    }
}
