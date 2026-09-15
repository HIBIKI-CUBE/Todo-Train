//
//  EstimateHeuristic.swift
//  Todo train
//

import Foundation

enum EstimateHeuristic {
    static let presets = EstimateChips.ticketPresets
    static let minimumSampleCount = 3
    static let defaultHighlightMinutes = 30
    /// Below this, an arrival is 開始忘れ→すぐ到着, not a ride to learn from.
    /// Genuine 早着 that already rode for a while stays in the sample.
    static let immediateArrivalLimitSeconds: TimeInterval = 60

    /// Median of sample durations in seconds. Returns nil if empty.
    static func medianSeconds(_ samples: [TimeInterval]) -> TimeInterval? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Nearest preset minutes in `presets` (ties prefer the lower preset).
    static func snapToPresetMinutes(_ seconds: TimeInterval) -> Int {
        let minutes = Int((seconds / 60).rounded())
        return presets.min(by: { lhs, rhs in
            let dL = abs(lhs - minutes)
            let dR = abs(rhs - minutes)
            if dL == dR { return lhs < rhs }
            return dL < dR
        }) ?? defaultHighlightMinutes
    }

    /// Suggestion for UI: snapped preset minutes + sample count. Nil if below minimum samples.
    static func suggestion(from samples: [TimeInterval]) -> (minutes: Int, sampleCount: Int)? {
        guard samples.count >= minimumSampleCount,
              let median = medianSeconds(samples) else {
            return nil
        }
        return (snapToPresetMinutes(median), samples.count)
    }

    static func caption(minutes: Int, sampleCount: Int) -> String {
        "過去の中央値 約\(minutes)分（\(sampleCount)件）"
    }

    struct ArrivedRide: Equatable, Sendable {
        var title: String
        var startedAt: Date
        var activeSeconds: TimeInterval
        var estimatedSeconds: Int
        var budgetSeconds: Int
        var extensionAddedSeconds: Int
        var extensionReasons: [String]
        var punctuality: ArrivalPunctuality
    }

    /// Arrived rides, optionally filtered by tag IDs (any match).
    static func arrivedRides(
        from sessions: [WorkSession],
        matchingAnyTagIDs tagIDs: Set<UUID>?
    ) -> [ArrivedRide] {
        sessions.compactMap { session -> ArrivedRide? in
            guard session.endedAt != nil, session.outcome == .arrived else { return nil }
            guard session.accumulatedActiveSeconds >= immediateArrivalLimitSeconds else { return nil }
            if let tagIDs, !tagIDs.isEmpty {
                let ticketTags = Set(session.ticket?.tags.map(\.id) ?? [])
                guard !ticketTags.isDisjoint(with: tagIDs) else { return nil }
            }
            let added = session.extensions.reduce(0) { $0 + $1.addedSeconds }
            let reasons = session.extensions.compactMap { extensionRecord -> String? in
                let reason = extensionRecord.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return reason.isEmpty ? nil : String(reason.prefix(40))
            }
            return ArrivedRide(
                title: session.ticket?.title ?? "",
                startedAt: session.startedAt,
                activeSeconds: session.accumulatedActiveSeconds,
                estimatedSeconds: session.estimatedSecondsAtStart,
                budgetSeconds: session.budgetSecondsAtStart,
                extensionAddedSeconds: added,
                extensionReasons: reasons,
                punctuality: Punctuality.classify(session)
            )
        }
    }

    /// Collect active seconds from arrived sessions, optionally filtered by tag IDs (any match).
    static func arrivedSamples(
        from sessions: [WorkSession],
        matchingAnyTagIDs tagIDs: Set<UUID>?
    ) -> [TimeInterval] {
        arrivedRides(from: sessions, matchingAnyTagIDs: tagIDs).map(\.activeSeconds)
    }
}
