//
//  FocusTimerPhaseTests.swift
//  Todo trainTests
//

import XCTest
@testable import Todo_train

final class FocusTimerPhaseTests: XCTestCase {
    func testFiveMinuteTicketThresholds() {
        let budget: TimeInterval = 5 * 60
        // approach floor 90s, final floor 30s
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 300, budgetSeconds: budget), .cruise)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 91, budgetSeconds: budget), .cruise)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 90, budgetSeconds: budget), .approach)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 31, budgetSeconds: budget), .approach)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 30, budgetSeconds: budget), .final)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: -1, budgetSeconds: budget), .overtime)
    }

    func testTwentyMinuteTicketScalesWithBudget() {
        let budget: TimeInterval = 20 * 60
        // approach = 25% = 300s, final = 10% = 120s
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 301, budgetSeconds: budget), .cruise)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 300, budgetSeconds: budget), .approach)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 121, budgetSeconds: budget), .approach)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 120, budgetSeconds: budget), .final)
    }

    func testSixtyMinuteTicketDoesNotWaitUntilOneMinute() {
        let budget: TimeInterval = 60 * 60
        // final = 10% = 360s (6 min) — not a fixed 60s
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 900, budgetSeconds: budget), .approach) // 15 min
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 360, budgetSeconds: budget), .final)
        XCTAssertEqual(FocusTimerPhase.phase(remaining: 61, budgetSeconds: budget), .final)
    }

    func testStateLabels() {
        XCTAssertNil(FocusTimerPhase.cruise.stateLabel)
        XCTAssertEqual(FocusTimerPhase.approach.stateLabel, "終盤")
        XCTAssertEqual(FocusTimerPhase.final.stateLabel, "まもなく")
        XCTAssertEqual(FocusTimerPhase.overtime.stateLabel, "超過")
    }
}
