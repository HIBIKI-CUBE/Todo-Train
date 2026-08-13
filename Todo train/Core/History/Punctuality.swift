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
    /// Finished ahead of the original estimate — a good result, not a miss.
    case early
    /// Overtime, or elapsed past the original estimate.
    case late
    /// Not an arrival (途中下車 / 放棄 / open).
    case notApplicable
}

/// Ephemeral joy — not a score. Played once, then discarded.
struct PunctualityMoment: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Any 到着. Punctuality only flavors copy; overtime still gets praised.
        case arrival(
            title: String,
            estimateSeconds: Int,
            actualSeconds: TimeInterval,
            punctuality: ArrivalPunctuality
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
    /// Flavors copy (定時到着 / 早着). Completion is praised regardless.
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

    /// On or ahead of the published timetable (not delayed).
    static func isAheadOfSchedule(_ punctuality: ArrivalPunctuality) -> Bool {
        switch punctuality {
        case .onTime, .early: true
        case .late, .notApplicable: false
        }
    }

    /// A service is on-time when it had at least one arrival and none were late.
    /// 早着 counts — finishing ahead is good. Empty days do not qualify.
    static func isOnTimeService(arrivedSessions: [WorkSession]) -> Bool {
        let arrived = arrivedSessions.filter { $0.outcome == .arrived }
        guard !arrived.isEmpty else { return false }
        return arrived.allSatisfy { isAheadOfSchedule(classify($0)) }
    }

    static func displayLabel(for session: WorkSession) -> String {
        switch classify(session) {
        case .onTime: "定時"
        case .early: "早着"
        default: HistoryStats.outcomeLabel(session.outcome)
        }
    }

    static func shouldCelebrateArrival(outcome: SessionOutcome?) -> Bool {
        outcome == .arrived
    }

    static func arrivalHeadline(_ punctuality: ArrivalPunctuality) -> String {
        switch punctuality {
        case .onTime: "定時到着"
        case .early: "早着"
        case .late, .notApplicable: "到着"
        }
    }

    /// 定時・早着は見積/実績を出す（いい結果）。超過は差を突き付けない。
    static func arrivalCaption(
        punctuality: ArrivalPunctuality,
        estimateSeconds: Int,
        actualSeconds: TimeInterval
    ) -> String? {
        switch punctuality {
        case .onTime, .early:
            durationCaption(estimateSeconds: estimateSeconds, actualSeconds: actualSeconds)
        case .late, .notApplicable:
            nil
        }
    }

    static func durationCaption(estimateSeconds: Int, actualSeconds: TimeInterval) -> String {
        let estimateMinutes = max(estimateSeconds, 0) / 60
        let actualMinutes = max(0, Int((actualSeconds / 60).rounded()))
        return "見積もり \(estimateMinutes)分 · 実績 \(actualMinutes)分"
    }
}
