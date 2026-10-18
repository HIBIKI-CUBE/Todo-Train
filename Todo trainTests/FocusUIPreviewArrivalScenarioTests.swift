//
//  FocusUIPreviewArrivalScenarioTests.swift
//  Todo trainTests
//
//  PR #157b 到着スクショ状態と PunctualityJudgment.judge の対応。
//

import Foundation
import Testing
import TodoTrainSync
@testable import Todo_train

@Suite("Focus UI preview arrival scenarios")
struct FocusUIPreviewArrivalScenarioTests {
    private func judge(
        estimatedStart: Int,
        active: TimeInterval,
        reestimates: [PunctualityJudgment.ReestimateCommit]
    ) -> PunctualityJudgment.Judgment {
        PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: true,
                activeSeconds: active,
                estimatedSecondsAtStart: estimatedStart,
                reestimates: reestimates
            )
        )
    }

    @Test func arrivalOnTimeTicketing() {
        let j = judge(estimatedStart: 30 * 60, active: 30 * 60, reestimates: [])
        #expect(j.outcome == .onTime)
        #expect(j.sealLuxury == 1.0)
    }

    @Test func arrivalOnTimeEarly() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 10 * 60,
                committedRemainingSeconds: 40 * 60
            ),
        ]
        let j = judge(estimatedStart: 30 * 60, active: 50 * 60, reestimates: events)
        #expect(j.outcome == .onTime)
        #expect(j.sealLuxury == 0.72)
    }

    @Test func arrivalOnTimeLate() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 25 * 60,
                committedRemainingSeconds: 15 * 60
            ),
        ]
        let j = judge(estimatedStart: 30 * 60, active: 40 * 60, reestimates: events)
        #expect(j.outcome == .onTime)
        #expect(j.sealLuxury == 0.34)
    }

    @Test func arrivalNotOnTime() {
        let j = judge(estimatedStart: 30 * 60, active: 5 * 60, reestimates: [])
        #expect(j.outcome == .early)
        #expect(j.sealLuxury == nil)
    }

    @Test func arrivalLateLog() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 12 * 60,
                committedRemainingSeconds: 38 * 60
            ),
        ]
        let j = judge(estimatedStart: 30 * 60, active: 58 * 60, reestimates: events)
        #expect(j.outcome == .late)
        #expect(j.sealLuxury == nil)
    }
}
