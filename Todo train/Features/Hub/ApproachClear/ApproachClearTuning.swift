//
//  ApproachClearTuning.swift
//  Todo train
//
//  Frozen timings for Hub approach clearance (issue #61).
//

import Foundation

nonisolated enum ApproachClearTuning {
    static let approachMs = 1_180.0
    static let goodCenter = 0.50
    static let goodHalfW = 0.066
    static let perfectHalfW0 = 0.013
    static let earlyGoodMul = 0.72
    static let earlyPerfMul = 0.85
    static let minPerfHalfMs = 12.0
    static let centerMin = 0.44
    static let centerMax = 0.58
    static let bandEdgeMin = 0.08
    static let bandEdgeMax = 0.92
    static let bandInset = 0.003

    static let sessionMs = 40_000.0
    static let pressLockMs = 50.0
    static let earlyJamMs = 260.0
    static let vibeApproachNear = 0.28
    static let lingerPerfectMs = 80.0
    static let lingerGoodMs = 55.0
    static let lingerMissMs = 150.0
    static let lingerTimeoutMs = 120.0
    static let nextAfterPerfectMs = 90.0
    static let nextAfterGoodMs = 80.0
    static let nextAfterMissMs = 140.0
    static let nextAfterTimeoutMs = 110.0
    static let bootGapMs = 260.0
    static let fullClearBonusMs = 120.0
    static let suspendedStandbyMs = 520.0

    static let interlockChance = 0.04
    static let barrierChance = 0.03
    static let interlockLeadMs = 40.0
    static let interlockStepMs = 45.0
    static let interlockLamps = 3
    static let interlockTailMs = 70.0
    static let barrierHoldMs = 120.0
    static let doubleBlipChance = 0.18

    static let comboIdleMs = 2_400.0
    static let comboHoldMs = 500.0
    static let heatPerPerfect = 1.0
    static let heatPerGood = 0.5
    static let heatTiers = [1.5, 3.0, 5.0]
    static let sessionFullClears = 14
    static let heatTightenMs = 180.0
    static let heatTightenGoodCap = 0.92
    static let idleBreathMinGapMs = 280.0

    static let approachMsJitter = [0.95, 1.0, 1.0, 1.04]
    static let goodHalfWJitter = [0.92, 0.97, 1.0, 1.04]
    static let perfectHalfWJitter = [0.92, 1.0, 1.0, 1.06]
    static let goodCenterJitter = [-0.03, -0.015, 0.0, 0.015, 0.03]

    static let heat: [HeatStep] = [
        HeatStep(approachMul: 1.00, goodMul: 1.00, perfMul: 1.00),
        HeatStep(approachMul: 0.92, goodMul: 0.90, perfMul: 0.92),
        HeatStep(approachMul: 0.85, goodMul: 0.80, perfMul: 0.86),
        HeatStep(approachMul: 0.80, goodMul: 0.72, perfMul: 0.80),
    ]

    nonisolated struct HeatStep: Equatable, Sendable {
        var approachMul: Double
        var goodMul: Double
        var perfMul: Double
    }

    static func tier(for heat: Double) -> Int {
        if heat >= heatTiers[2] { return 3 }
        if heat >= heatTiers[1] { return 2 }
        if heat >= heatTiers[0] { return 1 }
        return 0
    }

    static func heatStep(for tier: Int) -> HeatStep {
        heat[min(max(tier, 0), heat.count - 1)]
    }

    /// Positive half-up, matching the reference `Math.round`.
    static func jsRound(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    static var interlockSpanMs: Double {
        interlockLeadMs + interlockStepMs * Double(interlockLamps) + interlockTailMs
    }
}
