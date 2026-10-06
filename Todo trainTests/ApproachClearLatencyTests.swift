//
//  ApproachClearLatencyTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct ApproachClearLatencyTests {
    @Test func zeroLatencyLeavesTheTouchTime() {
        #expect(ApproachClearLatency.judgementMs(touchMs: 12_000, inputLatencyMs: 0) == 12_000)
    }

    @Test func positiveLatencyMovesTheTouchEarlier() {
        #expect(ApproachClearLatency.judgementMs(touchMs: 12_000, inputLatencyMs: 40) == 11_960)
        let approachMs = 1_180.0
        let delta = ApproachClearLatency.deltaMs(pressU: 0.5, visibleNeedleU: 0.4, approachMs: approachMs)
        #expect(abs(delta - 118) < 0.001)
    }

    @Test func latencyStaysZeroUntilThePressesAgree() {
        var estimate = ApproachClearLatencyEstimate()
        for _ in 0..<11 {
            estimate.record(rawDeltaMs: 18)
        }
        #expect(estimate.latencyMs == 0)
        #expect(estimate.samples.count == 11)

        estimate.record(rawDeltaMs: 18)
        #expect(estimate.latencyMs == 18)
    }

    @Test func wildGapsAreNotSamples() {
        var estimate = ApproachClearLatencyEstimate()
        estimate.record(rawDeltaMs: 200)
        estimate.record(rawDeltaMs: -120)
        #expect(estimate.samples.isEmpty)
        for _ in 0..<12 {
            estimate.record(rawDeltaMs: 16)
        }
        #expect(estimate.latencyMs == 16)
    }

    @Test func anUnsettledSpreadDoesNotMoveLatency() {
        var estimate = ApproachClearLatencyEstimate()
        let spread = [-70.0, -50, -30, -10, 10, 30, 50, 70, -70, -50, -30, -10]
        for sample in spread {
            estimate.record(rawDeltaMs: sample)
        }
        #expect(estimate.samples.count == 12)
        #expect(estimate.latencyMs == 0)
    }

    @Test func learnedLatencyIsCapped() {
        var estimate = ApproachClearLatencyEstimate()
        for _ in 0..<12 {
            estimate.record(rawDeltaMs: 50)
        }
        #expect(estimate.latencyMs == ApproachClearLatency.limitMs)
    }

    @Test func storeRoundTrip() {
        let name = "ApproachClearLatencyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        var estimate = ApproachClearLatencyEstimate()
        for _ in 0..<12 {
            estimate.record(rawDeltaMs: 12)
        }
        ApproachClearLatencyStore.save(estimate, defaults)
        #expect(ApproachClearLatencyStore.load(defaults) == estimate)
        defaults.removePersistentDomain(forName: name)
    }
}
