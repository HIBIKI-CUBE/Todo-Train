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

    func testSessionSnapshotMarksStaleWithoutClaimingOvertime() {
        let deadline = Date().addingTimeInterval(120)
        let snapshot = CockpitInstrumentSnapshot.session(
            deadline: deadline,
            budgetSeconds: 20 * 60,
            isOvertime: false,
            isStale: true,
            now: Date()
        )
        XCTAssertEqual(snapshot.headerState, "更新待ち")
        XCTAssertNotEqual(snapshot.phase, .overtime)
    }

    func testShortTimerLabelDropsSecondsWhenLimited() {
        XCTAssertEqual(
            CockpitFormat.shortTimerLabel(remaining: 12 * 60 + 5, limitedWidth: true),
            "12分"
        )
        XCTAssertEqual(
            CockpitFormat.shortTimerLabel(remaining: 5 * 60 + 5, limitedWidth: true),
            "5:05"
        )
    }

    func testDisplayModelSessionPaused() {
        let model = CockpitDisplayModel.session(
            title: "A",
            deadline: Date().addingTimeInterval(90),
            budgetSeconds: 300,
            isOvertime: false,
            isStale: false,
            isPaused: true
        )
        guard case .paused(let remaining) = model.clock else {
            return XCTFail("expected paused clock")
        }
        XCTAssertEqual(remaining, 90, accuracy: 1)
        XCTAssertEqual(model.headerState, "停車中")
    }

    func testDisplayModelSessionAwayPromptUsesAmberHeader() {
        let model = CockpitDisplayModel.session(
            title: "A",
            deadline: Date().addingTimeInterval(120),
            budgetSeconds: 300,
            isOvertime: false,
            isStale: false,
            checkInPrompt: "まだ乗ってる？"
        )
        XCTAssertEqual(model.headerState, "まだ乗ってる？")
        XCTAssertEqual(model.phase, .approach)
    }

    func testDisplayModelSessionOvertime() {
        let model = CockpitDisplayModel.session(
            title: "A",
            deadline: Date().addingTimeInterval(-10),
            budgetSeconds: 300,
            isOvertime: true,
            isStale: false
        )
        XCTAssertEqual(model.clock, .overtime)
        XCTAssertEqual(model.phase, .overtime)
    }

    func testTimerIntervalGuardsInvertedRange() {
        let start = Date()
        let end = start.addingTimeInterval(-30)
        let range = CockpitTimerInterval.countdown(to: end, from: start)
        XCTAssertEqual(range.lowerBound, start)
        XCTAssertEqual(range.upperBound, start)
    }
}
