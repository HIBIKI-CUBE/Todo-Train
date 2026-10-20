//
//  ApproachClearBands.swift
//  Todo train
//

import Foundation

nonisolated struct ApproachClearBands: Equatable, Sendable {
    var center: Double
    var goodHalfW: Double
    var perfectHalfW: Double
    var approachMs: Double
    var goodL: Double
    var goodR: Double
    var perfL: Double
    var perfR: Double
    var doubleBlip: Bool
    var ghostOffset: Double

    var goodEarlyMs: Double { (center - goodL) * approachMs }
    var goodLateMs: Double { (goodR - center) * approachMs }
    var perfEarlyMs: Double { (center - perfL) * approachMs }
    var perfLateMs: Double { (perfR - center) * approachMs }

    static let hidden = ApproachClearBands(
        center: ApproachClearTuning.goodCenter,
        goodHalfW: ApproachClearTuning.goodHalfW,
        perfectHalfW: ApproachClearTuning.perfectHalfW0,
        approachMs: ApproachClearTuning.approachMs,
        goodL: 0,
        goodR: 0,
        perfL: 0,
        perfR: 0,
        doubleBlip: false,
        ghostOffset: 0.14
    )

    /// `unit` is called six times: four jitter picks, double-blip, ghost offset.
    static func roll(tier: Int, unit: () -> Double) -> ApproachClearBands {
        let step = ApproachClearTuning.heatStep(for: tier)
        let approachMs = ApproachClearTuning.jsRound(
            ApproachClearTuning.approachMs
                * step.approachMul
                * pick(ApproachClearTuning.approachMsJitter, unit: unit)
        )
        let goodHalf = ApproachClearTuning.goodHalfW
            * step.goodMul
            * pick(ApproachClearTuning.goodHalfWJitter, unit: unit)
        let center = min(
            ApproachClearTuning.centerMax,
            max(
                ApproachClearTuning.centerMin,
                ApproachClearTuning.goodCenter + pick(ApproachClearTuning.goodCenterJitter, unit: unit)
            )
        )
        let floor = ApproachClearTuning.minPerfHalfMs / max(approachMs, 1)
        let perfectHalf = max(
            floor,
            ApproachClearTuning.perfectHalfW0
                * step.perfMul
                * pick(ApproachClearTuning.perfectHalfWJitter, unit: unit)
        )
        let doubleBlip = unit() < ApproachClearTuning.doubleBlipChance
        let ghost = 0.10 + unit() * 0.08
        return laidOut(
            center: center,
            goodHalfW: goodHalf,
            perfectHalfW: perfectHalf,
            approachMs: approachMs,
            doubleBlip: doubleBlip,
            ghostOffset: ghost
        )
    }

    static func laidOut(
        center: Double,
        goodHalfW: Double,
        perfectHalfW: Double,
        approachMs: Double,
        doubleBlip: Bool,
        ghostOffset: Double
    ) -> ApproachClearBands {
        let goodL = max(
            ApproachClearTuning.bandEdgeMin,
            center - goodHalfW * ApproachClearTuning.earlyGoodMul
        )
        let goodR = min(ApproachClearTuning.bandEdgeMax, center + goodHalfW)
        let perfL = max(
            goodL + ApproachClearTuning.bandInset,
            center - perfectHalfW * ApproachClearTuning.earlyPerfMul
        )
        let perfR = min(
            goodR - ApproachClearTuning.bandInset,
            center + perfectHalfW
        )
        return ApproachClearBands(
            center: center,
            goodHalfW: goodHalfW,
            perfectHalfW: perfectHalfW,
            approachMs: approachMs,
            goodL: goodL,
            goodR: goodR,
            perfL: perfL,
            perfR: perfR,
            doubleBlip: doubleBlip,
            ghostOffset: ghostOffset
        )
    }

    private static func pick(_ values: [Double], unit: () -> Double) -> Double {
        guard !values.isEmpty else { return 1 }
        let index = min(values.count - 1, max(0, Int(unit() * Double(values.count))))
        return values[index]
    }
}

nonisolated enum ApproachClearZone: Equatable, Sendable {
    case perfect
    case good
    case out
}

nonisolated extension ApproachClearBands {
    func zone(at u: Double) -> ApproachClearZone {
        if u >= perfL && u <= perfR { return .perfect }
        if u >= goodL && u <= goodR { return .good }
        return .out
    }
}
