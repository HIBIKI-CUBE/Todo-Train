//
//  SessionSmallFaceTests.swift
//  Todo trainTests
//

import XCTest
@testable import Todo_train

final class SessionSmallFaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testCruiseKeepsFocusPhaseAndCountsDown() {
        let face = make(remaining: 600, budget: 20 * 60)
        XCTAssertEqual(face.phase, .cruise)
        XCTAssertEqual(face.phase, FocusTimerPhase.phase(remaining: 600, budgetSeconds: 20 * 60))
        XCTAssertFalse(face.holdLamp.isLit)
        XCTAssertNil(face.pausedLabel)
        XCTAssertTrue(face.readout.countsWithTimerInterval)
    }

    func testApproachAndFinalMatchFocusWithoutLightingTheLamp() {
        let approach = make(remaining: 200, budget: 20 * 60)
        XCTAssertEqual(approach.phase, .approach)
        XCTAssertEqual(
            approach.phase,
            FocusTimerPhase.phase(remaining: 200, budgetSeconds: 20 * 60)
        )
        XCTAssertFalse(approach.holdLamp.isLit)

        let final = make(remaining: 100, budget: 20 * 60)
        XCTAssertEqual(final.phase, .final)
        XCTAssertFalse(final.holdLamp.isLit)
        XCTAssertTrue(final.readout.countsWithTimerInterval)
    }

    func testHeldPromptLightsTheLampWithoutRecoloringOrShowingTheQuestion() {
        let prompt = "まだ乗ってる？"
        let face = make(remaining: 600, budget: 20 * 60, checkInPrompt: prompt)
        XCTAssertEqual(face.phase, .cruise)
        XCTAssertEqual(face.title, "仕様書を書く")
        XCTAssertNil(face.pausedLabel)
        XCTAssertTrue(face.holdLamp.isLit)
        XCTAssertEqual(face.holdLamp.phase, .cruise)
        XCTAssertTrue(face.readout.countsWithTimerInterval)
    }

    func testBlankPromptDoesNotLightTheLamp() {
        let face = make(remaining: 600, budget: 20 * 60, checkInPrompt: "  ")
        XCTAssertFalse(face.holdLamp.isLit)
    }

    func testPausedIsAStaticStopDisplayAndDropsThePrompt() {
        let face = make(
            remaining: 90,
            budget: 300,
            isPaused: true,
            checkInPrompt: "まだ乗ってる？"
        )
        guard case .paused(let remaining) = face.readout else {
            return XCTFail("expected a static paused readout")
        }
        XCTAssertEqual(remaining, 90, accuracy: 0.001)
        XCTAssertEqual(face.pausedLabel, "停車中")
        XCTAssertFalse(face.holdLamp.isLit)
        XCTAssertFalse(face.readout.countsWithTimerInterval)
        XCTAssertEqual(face.phase, FocusTimerPhase.phase(remaining: 90, budgetSeconds: 300))
    }

    func testOvertimeUsesTheFocusOvertimePhaseAndIgnoresThePrompt() {
        let face = make(
            remaining: -10,
            budget: 300,
            isOvertime: true,
            checkInPrompt: "まだ乗ってる？"
        )
        XCTAssertEqual(face.readout, .overtime)
        XCTAssertEqual(face.phase, .overtime)
        XCTAssertFalse(face.holdLamp.isLit)
        XCTAssertFalse(face.readout.countsWithTimerInterval)
        XCTAssertNil(face.pausedLabel)
    }

    func testElapsedDeadlineIsOvertimeWithoutALiveCountdown() {
        let face = make(remaining: -1, budget: 300, isOvertime: false)
        XCTAssertEqual(face.readout, .overtime)
        XCTAssertEqual(face.phase, .overtime)
    }

    func testStaleDoesNotClaimOvertimeOrAHold() {
        let face = make(
            remaining: 120,
            budget: 300,
            isStale: true,
            checkInPrompt: "まだ乗ってる？"
        )
        XCTAssertEqual(face.readout, .stale)
        XCTAssertNotEqual(face.phase, .overtime)
        XCTAssertFalse(face.holdLamp.isLit)
        XCTAssertFalse(face.readout.countsWithTimerInterval)
    }

    func testHoldLampPhaseCanDifferFromTheInstrument() {
        let face = SessionSmallFace(
            title: "A",
            clock: .countdown(end: now.addingTimeInterval(60)),
            phase: .cruise,
            holdLamp: SessionSmallHoldLamp(isLit: true, phase: .overtime),
            pausedLabel: nil
        )
        XCTAssertEqual(face.phase, .cruise)
        XCTAssertTrue(face.holdLamp.isLit)
        XCTAssertEqual(face.holdLamp.phase, .overtime)
        XCTAssertNotEqual(face.holdLamp.phase, face.phase)
    }

    func testReducedLuminanceIsDarkerAndStillReadable() {
        let full = SessionSmallLuminance.resolve(reduced: false)
        let dim = SessionSmallLuminance.resolve(reduced: true)
        XCTAssertLessThan(dim.title, full.title)
        XCTAssertLessThan(dim.instrument, full.instrument)
        XCTAssertLessThan(dim.lamp, full.lamp)
        XCTAssertGreaterThan(dim.instrument, 0.3)
    }

    private func make(
        remaining: TimeInterval,
        budget: Int,
        isOvertime: Bool = false,
        isStale: Bool = false,
        isPaused: Bool = false,
        checkInPrompt: String? = nil
    ) -> SessionSmallFace {
        SessionSmallFace.make(
            title: "仕様書を書く",
            deadline: now.addingTimeInterval(remaining),
            budgetSeconds: budget,
            isOvertime: isOvertime,
            isStale: isStale,
            isPaused: isPaused,
            checkInPrompt: checkInPrompt,
            now: now
        )
    }
}
