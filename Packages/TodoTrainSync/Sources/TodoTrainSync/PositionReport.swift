import Foundation

/// 現在位置の報告から見込みと判見本を出す純粋関数。
public enum PositionReport: Sendable {
    /// 走行秒 `a` と割合 `p`（1 割刻み）から見込みの全体秒。10 割・未走行は nil。
    public static func projection(activeSeconds: TimeInterval, progress: Double) -> TimeInterval? {
        let p = (progress * 10).rounded() / 10
        if p >= 1.0 { return nil }
        if activeSeconds < 1 { return nil }
        return activeSeconds / p
    }

    /// 見込みの全体秒から走行を引いた残り（運転調整の記録と着時刻の共通根拠）。
    public static func projectedRemainingSeconds(
        activeSeconds: TimeInterval,
        progress: Double
    ) -> TimeInterval? {
        guard let total = projection(activeSeconds: activeSeconds, progress: progress) else { return nil }
        return total - activeSeconds
    }

    /// `now + (projection − activeSeconds)`。予算や残りタイマーは使わない。
    public static func projectedArrival(
        now: Date,
        activeSeconds: TimeInterval,
        progress: Double
    ) -> Date? {
        guard let remaining = projectedRemainingSeconds(activeSeconds: activeSeconds, progress: progress) else {
            return nil
        }
        return now.addingTimeInterval(remaining)
    }

    /// 運転調整で保存する見込みの全体秒（整数秒）。
    public static func projectedTotalSecondsInt(
        activeSeconds: TimeInterval,
        progress: Double
    ) -> Int? {
        guard let total = projection(activeSeconds: activeSeconds, progress: progress) else { return nil }
        return Int(total.rounded())
    }

    /// 運転調整で保存する `committedRemainingSeconds`。
    public static func committedRemainingSeconds(
        activeSeconds: TimeInterval,
        progress: Double
    ) -> Int? {
        guard let total = projectedTotalSecondsInt(activeSeconds: activeSeconds, progress: progress) else {
            return nil
        }
        return total - Int(activeSeconds.rounded())
    }

    /// 運転調整をいま確定したときの判の豪華さ（確定後の `sealLuxury` と同じ丸め）。
    public static func adjustLuxuryPreview(progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        let raw = PunctualityJudgment.adjustCeiling * (1 - p)
        return (raw * 100).rounded() / 100
    }

    /// 元の到着予定を過ぎていなければ回復運転を出す（超過中は運転調整のみ）。
    public static func showsRecoveryDeclaration(
        activeSeconds: TimeInterval,
        plannedBudgetSeconds: Int
    ) -> Bool {
        guard plannedBudgetSeconds > 0 else { return false }
        return activeSeconds < TimeInterval(plannedBudgetSeconds)
    }
}
