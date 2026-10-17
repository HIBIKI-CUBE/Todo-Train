//
//  Punctuality.swift
//  Todo train
//
//  定時 = 当初見積もりに対する実績の帯域内。通貨化しない。
//

import Foundation
import TodoTrainSync

/// How an arrived session sits against its published timetable (original estimate).
nonisolated enum ArrivalPunctuality: Equatable, Sendable {
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
    /// 到着祝祭が締める乗車。定時運行の案内と、乗客を降りたあとの行き先では nil。
    let arrivedSessionID: UUID?
    /// 乗客を降りたあとは、締めは PassengerRide に既にある。検札は次の切符の指名だけ。
    let recordsWorkSessionStamp: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        arrivedSessionID: UUID? = nil,
        recordsWorkSessionStamp: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.arrivedSessionID = arrivedSessionID
        self.recordsWorkSessionStamp = recordsWorkSessionStamp
    }

    /// Readable but not a sit-and-wait celebration. Keep in sync with overlay phases.
    /// Used by 定時運行 capsule only; arrivals use ArrivalInvalidateOverlay (gesture).
    static let presentationMilliseconds = 900
}

enum Punctuality {
    static func rideInput(for session: WorkSession) -> PunctualityJudgment.RideInput {
        let reestimates = session.reestimateEvents
            .filter { $0.undoneAt == nil }
            .map {
                PunctualityJudgment.ReestimateCommit(
                    reestimateIndex: $0.reestimateIndex,
                    activeSeconds: $0.activeSeconds,
                    committedRemainingSeconds: $0.committedRemainingSeconds
                )
            }
        return PunctualityJudgment.RideInput(
            arrived: session.outcome == .arrived,
            activeSeconds: session.accumulatedActiveSeconds,
            estimatedSecondsAtStart: session.estimatedSecondsAtStart,
            reestimates: reestimates
        )
    }

    static func judgment(for session: WorkSession) -> PunctualityJudgment.Judgment {
        PunctualityJudgment.judge(rideInput(for: session))
    }

    static func classify(
        outcome: SessionOutcome?,
        elapsedSeconds: TimeInterval,
        estimateSeconds: Int,
        overtimeResolution: OvertimeResolution?,
        reestimates: [PunctualityJudgment.ReestimateCommit] = []
    ) -> ArrivalPunctuality {
        guard outcome == .arrived else { return .notApplicable }
        let input = PunctualityJudgment.RideInput(
            arrived: true,
            activeSeconds: elapsedSeconds,
            estimatedSecondsAtStart: estimateSeconds,
            reestimates: reestimates
        )
        return mapOutcome(PunctualityJudgment.judge(input).outcome)
    }

    static func classify(_ session: WorkSession) -> ArrivalPunctuality {
        mapOutcome(judgment(for: session).outcome)
    }

    private static func mapOutcome(_ outcome: PunctualityJudgment.Outcome) -> ArrivalPunctuality {
        switch outcome {
        case .onTime: .onTime
        case .early: .early
        case .late: .late
        case .notApplicable: .notApplicable
        }
    }

    /// On or ahead of the published timetable (not delayed).
    static func isAheadOfSchedule(_ punctuality: ArrivalPunctuality) -> Bool {
        punctuality == .onTime
    }

    /// A service is on-time when it had at least one arrival and none were late.
    /// 早着は定時運行に入れない。Empty days do not qualify.
    static func isOnTimeService(arrivedSessions: [WorkSession]) -> Bool {
        let arrived = arrivedSessions.filter { $0.outcome == .arrived }
        guard !arrived.isEmpty else { return false }
        return arrived.allSatisfy { classify($0) == .onTime }
    }

    static func judgedEstimateSeconds(for session: WorkSession) -> Int {
        Int(judgment(for: session).judgedTotalSeconds.rounded())
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

    static func arrivalCaption(for session: WorkSession) -> String? {
        let punctuality = classify(session)
        return arrivalCaption(
            punctuality: punctuality,
            estimateSeconds: judgedEstimateSeconds(for: session),
            actualSeconds: session.accumulatedActiveSeconds
        )
    }

    static func durationCaption(estimateSeconds: Int, actualSeconds: TimeInterval) -> String {
        let estimateMinutes = max(estimateSeconds, 0) / 60
        let actualMinutes = max(0, Int((actualSeconds / 60).rounded()))
        return "見積もり \(estimateMinutes)分 · 実績 \(actualMinutes)分"
    }
}
