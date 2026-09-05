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
    /// One or two short questions for 車内放送. Advice-free. Empty → caller uses fallback.
    func checkInLines(title: String, estimatedMinutes: Int) async -> [String]
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

    func checkInLines(title: String, estimatedMinutes: Int) async -> [String] {
        [CheckInCopy.fallback(title: title)]
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// On-device one-liner at board time. Never a conversation. PCC is not used here.
struct OnDeviceCoachingEngine: CoachingEngine {
    func suggestSplit(for title: String, estimatedMinutes: Int) async -> SplitSuggestion? {
        await HeuristicCoachingEngine().suggestSplit(for: title, estimatedMinutes: estimatedMinutes)
    }

    func dailyReview(sessions: [WorkSession]) async -> String? {
        await HeuristicCoachingEngine().dailyReview(sessions: sessions)
    }

    func checkInLines(title: String, estimatedMinutes: Int) async -> [String] {
        let fallback = [CheckInCopy.fallback(title: title)]
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return fallback }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            あなたは作業中の短い問いだけを返す。アドバイス・励まし・分割案・絵文字は禁止。
            疑問形の日本語を1行。40文字以内。タスク名以外の固有情報を捏造しない。
            """
        )
        let prompt = "タスク名: \(title)\n見積もり: \(estimatedMinutes)分\nまだこれに乗っているかを聞く1行。"
        do {
            let response = try await session.respond(to: prompt)
            let line = response.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return fallback }
            return [line]
        } catch {
            return fallback
        }
    }
}

struct PCCCoachingEngine: CoachingEngine {
    func suggestSplit(for title: String, estimatedMinutes: Int) async -> SplitSuggestion? {
        // Stub: wire Private Cloud Compute when available on device.
        await HeuristicCoachingEngine().suggestSplit(for: title, estimatedMinutes: estimatedMinutes)
    }

    func dailyReview(sessions: [WorkSession]) async -> String? {
        await HeuristicCoachingEngine().dailyReview(sessions: sessions)
    }

    func checkInLines(title: String, estimatedMinutes: Int) async -> [String] {
        await HeuristicCoachingEngine().checkInLines(title: title, estimatedMinutes: estimatedMinutes)
    }
}
#endif

enum CoachingEngineFactory {
    static func make() -> any CoachingEngine {
        #if canImport(FoundationModels)
        OnDeviceCoachingEngine()
        #else
        HeuristicCoachingEngine()
        #endif
    }
}
