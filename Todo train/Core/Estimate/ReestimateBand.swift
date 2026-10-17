//
//  ReestimateBand.swift
//  Todo train
//

import Foundation

enum ReestimateBand {
    private static let gaugeMaxRemainingMinutes = 60

    struct ShownBand: Equatable {
        var lowTotalSeconds: Int
        var highTotalSeconds: Int
        var headline: String
        var clippedAtMaxRemaining: Bool
    }

    /// 走行時間 ÷（答え±5%）だけで帯を作る。
    static func shown(
        activeSeconds: TimeInterval,
        progress: Double
    ) -> ShownBand? {
        guard activeSeconds >= 180 else { return nil }
        let p = min(max(progress, 0.1), 0.9)
        let lowDenom = min(p + 0.05, 1.0)
        let highDenom = max(p - 0.05, 0.01)
        let lowTotal = Int((activeSeconds / lowDenom).rounded())
        let highTotal = Int((activeSeconds / highDenom).rounded())
        let span = remainingSpan(activeSeconds: activeSeconds, lowTotalSeconds: lowTotal, highTotalSeconds: highTotal)
        let clipped = span?.clippedAtMax == true
        let headline = headline(
            progress: p,
            activeSeconds: activeSeconds,
            lowMinutes: lowTotal / 60,
            highMinutes: highTotal / 60,
            clippedAtMaxRemaining: clipped
        )
        return ShownBand(
            lowTotalSeconds: lowTotal,
            highTotalSeconds: highTotal,
            headline: headline,
            clippedAtMaxRemaining: clipped
        )
    }

    static func headline(
        progress: Double,
        activeSeconds: TimeInterval,
        lowMinutes: Int,
        highMinutes: Int,
        clippedAtMaxRemaining: Bool
    ) -> String {
        let low = max(lowMinutes, 1)
        let high = max(highMinutes, low)
        if clippedAtMaxRemaining {
            return "全体\(low)分以上"
        }
        if progress >= 0.3 {
            let totalMinutes = activeSeconds / progress / 60.0
            let rounded = max(5, Int((totalMinutes / 5.0).rounded()) * 5)
            return "全体\(rounded)分前後"
        }
        return "全体\(low)〜\(high)分"
    }

    struct RemainingSpan: Equatable {
        var lowRemainingMinutes: Int
        var highRemainingMinutes: Int
        var clippedAtMax: Bool
    }

    /// 残り時間ゲージ用。帯の全体秒から、今の走行を引いた残りの幅。
    static func remainingSpan(
        activeSeconds: TimeInterval,
        band: ShownBand
    ) -> RemainingSpan? {
        remainingSpan(
            activeSeconds: activeSeconds,
            lowTotalSeconds: band.lowTotalSeconds,
            highTotalSeconds: band.highTotalSeconds
        )
    }

    static func remainingSpan(
        activeSeconds: TimeInterval,
        lowTotalSeconds: Int,
        highTotalSeconds: Int
    ) -> RemainingSpan? {
        let active = Int(activeSeconds.rounded())
        let lowRemain = max(0, lowTotalSeconds - active)
        let highRemain = max(0, highTotalSeconds - active)
        let lowMin = max(1, (lowRemain + 59) / 60)
        let highMin = max(lowMin, (highRemain + 59) / 60)
        let cappedHigh = min(highMin, gaugeMaxRemainingMinutes)
        let clipped = highMin > gaugeMaxRemainingMinutes
        return RemainingSpan(
            lowRemainingMinutes: min(lowMin, gaugeMaxRemainingMinutes),
            highRemainingMinutes: cappedHigh,
            clippedAtMax: clipped
        )
    }
}
