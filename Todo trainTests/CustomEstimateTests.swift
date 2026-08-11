//
//  CustomEstimateTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

struct CustomEstimateTests {
    @Test func clampMinutes_withinRange() {
        #expect(CustomEstimate.clampMinutes(0) == 1)
        #expect(CustomEstimate.clampMinutes(23) == 23)
        #expect(CustomEstimate.clampMinutes(99) == 60)
    }

    @Test func parseMinutes_acceptsValidInput() {
        #expect(CustomEstimate.parseMinutes(from: "23") == 23)
        #expect(CustomEstimate.parseMinutes(from: " 45 ") == 45)
        #expect(CustomEstimate.parseMinutes(from: "0") == nil)
        #expect(CustomEstimate.parseMinutes(from: "61") == nil)
        #expect(CustomEstimate.parseMinutes(from: "abc") == nil)
    }
}
