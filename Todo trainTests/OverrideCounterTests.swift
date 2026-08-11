//
//  OverrideCounterTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct OverrideCounterTests {
    @Test func inMemory_incrementsPerDayKeyIndependently() {
        let counter = InMemoryOverrideCounter()
        #expect(counter.increment(forDayKey: "2026-08-11") == 1)
        #expect(counter.increment(forDayKey: "2026-08-11") == 2)
        #expect(counter.count(forDayKey: "2026-08-12") == 0)
        #expect(counter.increment(forDayKey: "2026-08-12") == 1)
        counter.reset(forDayKey: "2026-08-11")
        #expect(counter.count(forDayKey: "2026-08-11") == 0)
        #expect(counter.count(forDayKey: "2026-08-12") == 1)
    }
}
