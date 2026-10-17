//
//  PunctualityPresentation.swift
//  Todo train
//
//  VoiceOver・乗務記録・初回説明。判定は Punctuality.judgment だけ。
//

import Foundation
import TodoTrainSync

enum PunctualityFirstTimeTips {
    static let homeStorageKey = "punctuality.tip.home"
    static let sealStorageKey = "punctuality.tip.seal"

    static let homeLine = "ホーム＝定時に着く幅"
    static let sealLine = "定時に着いた切符に押す判"
}

enum PunctualityPresentation {
    static func ridingSealTier(
        judgment: PunctualityJudgment.Judgment,
        reestimates: [PunctualityJudgment.ReestimateCommit]
    ) -> PunctualityJudgment.OnTimeSealTier? {
        switch judgment.source {
        case .original:
            return .ticketing
        case .reestimate(let index):
            guard let event = reestimates.first(where: { $0.reestimateIndex == index }) else {
                return .ticketing
            }
            let half = judgment.judgedTotalSeconds / 2
            return event.activeSeconds <= half ? .earlyReestimate : .lateReestimate
        }
    }

    static func homeBandFractions(
        judgment: PunctualityJudgment.Judgment,
        budgetSeconds: Int
    ) -> (start: Double, end: Double)? {
        let budget = Double(max(budgetSeconds, 1))
        let start = judgment.lowerBound / budget
        let end = judgment.upperBound / budget
        guard end > 0, start < 2 else { return nil }
        return (min(max(start, 0), 1.25), min(max(end, 0), 1.25))
    }

    static func minutesUntilHome(
        judgment: PunctualityJudgment.Judgment,
        activeSeconds: TimeInterval
    ) -> Int? {
        guard judgment.signal == .green else { return nil }
        let remaining = judgment.lowerBound - activeSeconds
        guard remaining > 0 else { return nil }
        return max(1, Int((remaining / 60).rounded(.up)))
    }

    static func signalAccessibilityLabel(
        judgment: PunctualityJudgment.Judgment,
        activeSeconds: TimeInterval
    ) -> String {
        switch judgment.signal {
        case .green:
            if let minutes = minutesUntilHome(judgment: judgment, activeSeconds: activeSeconds) {
                return "ホームまであと\(minutes)分"
            }
            return "ホームの手前"
        case .yellow:
            return "ホームの中"
        case .off:
            return "ホームを過ぎました"
        }
    }

    static func sealSampleAccessibilityLabel(
        tier: PunctualityJudgment.OnTimeSealTier
    ) -> String {
        let name = switch tier {
        case .ticketing: "発券時の見積もり"
        case .earlyReestimate: "走行前半の見積もり直し"
        case .lateReestimate: "走行後半の見積もり直し"
        }
        return "かかっている判：\(name)"
    }

    static func stampAccessibilityLabel(
        punctuality: ArrivalPunctuality,
        includesCornerSeal: Bool
    ) -> String {
        let center = switch punctuality {
        case .onTime: includesCornerSeal ? "定時の角判" : "定時"
        case .early: "早着"
        case .late, .notApplicable: "到着"
        }
        return "\(center)の印"
    }

    static func onTimeArrivalVoiceLine() -> String { "定時到着です" }

    struct RideLogLine: Equatable, Sendable {
        var text: String
    }

    static func rideLogLines(for session: WorkSession) -> [RideLogLine] {
        var lines: [RideLogLine] = []
        let originalMinutes = max(session.estimatedSecondsAtStart, 0) / 60
        lines.append(RideLogLine(text: "最初の見積もり \(originalMinutes)分"))

        let activeReestimates = session.reestimateEvents.filter { $0.undoneAt == nil }
        if let last = activeReestimates.last {
            let total = Int(last.activeSeconds.rounded()) + last.committedRemainingSeconds
            lines.append(RideLogLine(text: "見積もり直し \(max(total, 0) / 60)分"))
        }

        let actualMinutes = max(0, Int((session.accumulatedActiveSeconds / 60).rounded()))
        lines.append(RideLogLine(text: "実際 \(actualMinutes)分"))

        if let progressLine = progressComparisonLine(for: session) {
            lines.append(RideLogLine(text: progressLine))
        }
        return lines
    }

    static func progressComparisonLine(for session: WorkSession) -> String? {
        guard let event = session.reestimateEvents
            .filter({ $0.undoneAt == nil })
            .last(where: { $0.progressAnswer != nil }),
            let progress = event.progressAnswer,
            progress > 0
        else { return nil }
        let answeredTenth = Int((progress * 10).rounded())
        guard answeredTenth > 0 else { return nil }
        let impliedTotal = event.activeSeconds / progress
        guard impliedTotal > 0 else { return nil }
        let actualTenth = Int(((session.accumulatedActiveSeconds / impliedTotal) * 10).rounded())
        return "\(answeredTenth)割と答えた時点 → 実際は全体の\(max(actualTenth, 0))割"
    }
}
