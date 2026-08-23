//
//  CoachingEngine.swift
//  Todo train
//

import Foundation

struct SplitSuggestion: Equatable, Sendable {
    var segments: [String]
    var note: String?
}

protocol CoachingEngine: Sendable {
    func suggestSplit(for title: String, estimatedMinutes: Int) async -> SplitSuggestion?
    func dailyReview(sessions: [WorkSession]) async -> String?
}

struct HeuristicCoachingEngine: CoachingEngine {
    func suggestSplit(for title: String, estimatedMinutes: Int) async -> SplitSuggestion? {
        guard estimatedMinutes > 30 else { return nil }
        let half = estimatedMinutes / 2
        let remainder = estimatedMinutes - half
        return SplitSuggestion(
            segments: [
                "\(title)（前半）",
                "\(title)（後半）"
            ],
            note: "約 \(half) 分 + \(remainder) 分に分ける案です（ヒューリスティック）。"
        )
    }

    func dailyReview(sessions: [WorkSession]) async -> String? {
        let ended = sessions.filter { $0.endedAt != nil }
        guard !ended.isEmpty else { return nil }
        let arrived = ended.filter { $0.outcome == .arrived }.count
        let totalMinutes = Int(ended.reduce(0.0) { $0 + $1.accumulatedActiveSeconds } / 60)
        return "今日は \(arrived) 件到着、合計 \(totalMinutes) 分でした。"
    }
}

#if canImport(FoundationModels)
struct PCCCoachingEngine: CoachingEngine {
    func suggestSplit(for title: String, estimatedMinutes: Int) async -> SplitSuggestion? {
        // Stub: wire Private Cloud Compute when available on device.
        await HeuristicCoachingEngine().suggestSplit(for: title, estimatedMinutes: estimatedMinutes)
    }

    func dailyReview(sessions: [WorkSession]) async -> String? {
        await HeuristicCoachingEngine().dailyReview(sessions: sessions)
    }
}
#endif
