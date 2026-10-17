//
//  ReestimateBandTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

struct ReestimateBandTests {
    @Test func headline_usesRoundedTotalWhenProgressAtLeast30Percent() {
        let band = ReestimateBand.shown(activeSeconds: 1_800, progress: 0.4)
        #expect(band?.headline == "全体45分前後")
    }

    @Test func headline_usesRangeWhenProgressBelow30Percent() {
        let band = ReestimateBand.shown(activeSeconds: 1_800, progress: 0.2)
        #expect(band?.headline.contains("〜") == true)
        #expect(band?.headline.contains("前後") == false)
    }

    @Test func headline_clipsAtGaugeMaxRemaining() {
        let headline = ReestimateBand.headline(
            progress: 0.2,
            activeSeconds: 3_600,
            lowMinutes: 10,
            highMinutes: 90,
            clippedAtMaxRemaining: true
        )
        #expect(headline == "全体10分以上")
    }
}
