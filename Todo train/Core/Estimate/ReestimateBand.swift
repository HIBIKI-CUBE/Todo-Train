//
//  ReestimateBand.swift
//  Todo train
//

import Foundation

enum ReestimateBand {
    struct ShownBand: Equatable {
        var lowTotalSeconds: Int
        var highTotalSeconds: Int
        var headline: String
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
        let headline = headline(lowMinutes: lowTotal / 60, highMinutes: highTotal / 60)
        return ShownBand(
            lowTotalSeconds: lowTotal,
            highTotalSeconds: highTotal,
            headline: headline
        )
    }

    static func headline(lowMinutes: Int, highMinutes: Int) -> String {
        let low = max(lowMinutes, 1)
        let high = max(highMinutes, low)
        if high >= 60 && high - low >= 20 {
            return "全体60分以上"
        }
        if low == high {
            return "全体\(low)分前後"
        }
        return "全体\(low)〜\(high)分"
    }

    /// 残り時間ゲージ用。帯の全体秒から、今の走行を引いた残りの幅。
    static func remainingSpan(
        activeSeconds: TimeInterval,
        band: ShownBand
    ) -> (lowRemainingMinutes: Int, highRemainingMinutes: Int)? {
        let lowRemain = max(0, band.lowTotalSeconds - Int(activeSeconds.rounded()))
        let highRemain = max(0, band.highTotalSeconds - Int(activeSeconds.rounded()))
        let lowMin = max(1, (lowRemain + 59) / 60)
        let highMin = max(lowMin, (highRemain + 59) / 60)
        return (lowMin, min(highMin, 60))
    }
}
