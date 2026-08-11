//
//  EstimateHeuristic.swift
//  Todo train
//

import Foundation

enum EstimateHeuristic {
    static let presets = EstimateChips.ticketPresets
    static let minimumSampleCount = 3
    static let defaultHighlightMinutes = 30

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

    /// Collect active seconds from arrived sessions, optionally filtered by tag IDs (any match).
    static func arrivedSamples(
        from sessions: [WorkSession],
        matchingAnyTagIDs tagIDs: Set<UUID>?
    ) -> [TimeInterval] {
        sessions.compactMap { session -> TimeInterval? in
            guard session.endedAt != nil, session.outcome == .arrived else { return nil }
            if let tagIDs, !tagIDs.isEmpty {
                let ticketTags = Set(session.ticket?.tags.map(\.id) ?? [])
                guard !ticketTags.isDisjoint(with: tagIDs) else { return nil }
            }
            return session.accumulatedActiveSeconds
        }
    }
}
