//
//  ReestimateBandTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

struct ReestimateBandTests {
    @Test func band_usesActiveOverProgress() {
        let band = ReestimateBand.shown(activeSeconds: 600, progress: 0.5)
        #expect(band != nil)
        #expect(band?.lowTotalSeconds == 1_091)
        #expect(band?.highTotalSeconds == 1_333)
    }

    @Test func band_hiddenUnderThreeMinutes() {
        #expect(ReestimateBand.shown(activeSeconds: 179, progress: 0.5) == nil)
    }
}
