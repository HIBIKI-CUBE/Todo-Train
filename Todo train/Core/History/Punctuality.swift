//
//  Punctuality.swift
//  Todo train
//
//  定時 = 当初見積もりに対する実績の帯域内。通貨化しない。
//

import Foundation

/// How an arrived session sits against its published timetable (original estimate).
enum ArrivalPunctuality: Equatable, Sendable {
    /// Within the on-time band of the original estimate.
    case onTime
    /// Finished too far ahead of the original estimate.
    case early
    /// Overtime, or elapsed past the original estimate.
    case late
    /// Not an arrival (途中下車 / 放棄 / open).
    case notApplicable
}

/// Ephemeral joy — not a score. Played once, then discarded.
struct PunctualityMoment: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Any 到着. `isOnTime` only flavors copy; overtime still gets praised.
        case arrival(
            title: String,
            estimateSeconds: Int,
            actualSeconds: TimeInterval,
            isOnTime: Bool
        )
        case onTimeService
    }

    let id: UUID
    let kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// Readable but not a sit-and-wait celebration. Keep in sync with overlay phases.
    static let presentationMilliseconds = 800
}

enum Punctuality {
    /// Allowed early margin as a fraction of the original estimate.
    static let earlyRatio: Double = 0.15
    /// Floor so a 5-minute ticket still has a real window (~45s).
    static let minimumSlackSeconds: TimeInterval = 45
    /// Clock jitter when tapping 到着 at the last beat.
    static let lateGraceSeconds: TimeInterval = 0.5

    static func slack(estimateSeconds: Int) -> TimeInterval {
        let estimate = TimeInterval(max(estimateSeconds, 1))
        return max(estimate * earlyRatio, minimumSlackSeconds)
    }

    /// Classify against the **original** estimate, not the extended budget.
    /// Used only to flavor copy (定時到着). Completion is praised regardless.
    static func classify(
        outcome: SessionOutcome?,
        elapsedSeconds: TimeInterval,
        estimateSeconds: Int,
        overtimeResolution: OvertimeResolution?
    ) -> ArrivalPunctuality {
        guard outcome == .arrived else { return .notApplicable }
        if overtimeResolution != nil { return .late }

        let estimate = TimeInterval(max(estimateSeconds, 1))
        if elapsedSeconds > estimate + lateGraceSeconds {
            return .late
        }

        let lowerBound = estimate - slack(estimateSeconds: estimateSeconds)
        if elapsedSeconds < lowerBound {
            return .early
        }
        return .onTime
    }

    static func classify(_ session: WorkSession) -> ArrivalPunctuality {
        classify(
            outcome: session.outcome,
            elapsedSeconds: session.accumulatedActiveSeconds,
            estimateSeconds: session.estimatedSecondsAtStart,
            overtimeResolution: session.overtimeResolution
        )
    }

    /// A service is on-time only when it had at least one arrival and every arrival was on-time.
    /// Empty days and 早着-only days do not qualify (nothing to farm by skipping work).
    static func isOnTimeService(arrivedSessions: [WorkSession]) -> Bool {
        let arrived = arrivedSessions.filter { $0.outcome == .arrived }
        guard !arrived.isEmpty else { return false }
        return arrived.allSatisfy { classify($0) == .onTime }
    }

    static func displayLabel(for session: WorkSession) -> String {
        if classify(session) == .onTime {
            return "定時"
        }
        return HistoryStats.outcomeLabel(session.outcome)
    }

    static func shouldCelebrateArrival(outcome: SessionOutcome?) -> Bool {
        outcome == .arrived
    }

    static func arrivalHeadline(isOnTime: Bool) -> String {
        isOnTime ? "定時到着" : "到着"
    }

    /// Match line only when 定時. Overtime/early celebrations omit the gap so completion stays first.
    static func arrivalCaption(
        isOnTime: Bool,
        estimateSeconds: Int,
        actualSeconds: TimeInterval
    ) -> String? {
        guard isOnTime else { return nil }
        return durationCaption(estimateSeconds: estimateSeconds, actualSeconds: actualSeconds)
    }

    static func durationCaption(estimateSeconds: Int, actualSeconds: TimeInterval) -> String {
        let estimateMinutes = max(estimateSeconds, 0) / 60
        let actualMinutes = max(0, Int((actualSeconds / 60).rounded()))
        return "見積もり \(estimateMinutes)分 · 実績 \(actualMinutes)分"
    }
}
