//
//  TicketStampBundleAssembly.swift
//  Todo train
//
//  検札済み切符を運行日ごとの束にする。表示専用 — 永続化しない。
//

import Foundation
import TodoTrainSync

enum TicketStampBundleAssembly {
    struct ServiceDayInput: Equatable, Sendable {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var calendarDayKey: String
    }

    struct ReestimateInput: Equatable, Sendable {
        var reestimateIndex: Int
        var activeSeconds: TimeInterval
        var committedRemainingSeconds: Int
        var undoneAt: Date?
    }

    struct SessionInput: Equatable, Sendable {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var outcome: SessionOutcome?
        var arrivalStampedAt: Date?
        var title: String
        var estimatedSecondsAtStart: Int
        var accumulatedActiveSeconds: TimeInterval
        var reestimates: [ReestimateInput]
    }

    struct Stamp: Equatable, Sendable, Identifiable {
        var id: UUID { sessionID }
        var sessionID: UUID
        var serviceDayID: UUID
        var title: String
        var stampedAt: Date
        var punctuality: ArrivalPunctuality
        var sealTier: PunctualityJudgment.OnTimeSealTier?
        var stampSeason: PunctualityJudgment.StampSeason
        var stampTimeOfDay: PunctualityJudgment.StampTimeOfDay
        var judgedEstimateMinutes: Int
        var originalEstimateMinutes: Int
        var reestimateTotalMinutes: Int?
        var actualMinutes: Int
    }

    struct DayBundle: Equatable, Sendable, Identifiable {
        var id: UUID { serviceDayID }
        var serviceDayID: UUID
        var calendarDayKey: String
        var startedAt: Date
        var stamps: [Stamp]
    }

    struct FlatStamp: Equatable, Sendable, Identifiable {
        var id: UUID { stamp.sessionID }
        var stamp: Stamp
        var dayBoundaryBefore: Bool
    }

    static func includesInBundle(_ session: SessionInput) -> Bool {
        guard session.outcome == .arrived, session.arrivalStampedAt != nil else { return false }
        return true
    }

    static func matchingServiceDayID(
        startedAt: Date,
        serviceDays: [ServiceDayInput]
    ) -> UUID? {
        serviceDays
            .filter { day in
                let end = day.endedAt ?? .distantFuture
                return startedAt >= day.startedAt && startedAt < end
            }
            .max { lhs, rhs in
                if lhs.startedAt != rhs.startedAt {
                    return lhs.startedAt < rhs.startedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }?
            .id
    }

    static func buildDayBundles(
        sessions: [SessionInput],
        serviceDays: [ServiceDayInput]
    ) -> [DayBundle] {
        let stamped = sessions.filter(includesInBundle)
        var byDay: [UUID: [Stamp]] = [:]
        var dayMeta: [UUID: ServiceDayInput] = [:]

        for session in stamped {
            guard let dayID = matchingServiceDayID(startedAt: session.startedAt, serviceDays: serviceDays),
                  let day = serviceDays.first(where: { $0.id == dayID }),
                  let stampedAt = session.arrivalStampedAt
            else { continue }
            let stamp = makeStamp(session: session, serviceDayID: dayID, stampedAt: stampedAt)
            byDay[dayID, default: []].append(stamp)
            dayMeta[dayID] = day
        }

        return byDay.keys
            .compactMap { dayID -> DayBundle? in
                guard let day = dayMeta[dayID] else { return nil }
                let stamps = (byDay[dayID] ?? []).sorted { $0.stampedAt < $1.stampedAt }
                return DayBundle(
                    serviceDayID: dayID,
                    calendarDayKey: day.calendarDayKey,
                    startedAt: day.startedAt,
                    stamps: stamps
                )
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func flatten(_ bundles: [DayBundle]) -> [FlatStamp] {
        var result: [FlatStamp] = []
        for bundle in bundles.sorted(by: { $0.startedAt < $1.startedAt }) {
            for (index, stamp) in bundle.stamps.enumerated() {
                result.append(
                    FlatStamp(
                        stamp: stamp,
                        dayBoundaryBefore: index == 0
                    )
                )
            }
        }
        return result
    }

    static func bundle(
        forCalendarDayKey dayKey: String,
        in bundles: [DayBundle]
    ) -> DayBundle? {
        bundles.first { $0.calendarDayKey == dayKey }
    }

    private static func makeStamp(
        session: SessionInput,
        serviceDayID: UUID,
        stampedAt: Date
    ) -> Stamp {
        let commits = session.reestimates
            .filter { $0.undoneAt == nil }
            .map {
                PunctualityJudgment.ReestimateCommit(
                    reestimateIndex: $0.reestimateIndex,
                    activeSeconds: $0.activeSeconds,
                    committedRemainingSeconds: $0.committedRemainingSeconds
                )
            }
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: true,
                activeSeconds: session.accumulatedActiveSeconds,
                estimatedSecondsAtStart: session.estimatedSecondsAtStart,
                reestimates: commits
            )
        )
        let punctuality = mapOutcome(judgment.outcome)
        let reestimateTotal: Int? = {
            guard let last = session.reestimates.filter({ $0.undoneAt == nil }).last else { return nil }
            let total = Int(last.activeSeconds.rounded()) + last.committedRemainingSeconds
            return max(total, 0) / 60
        }()
        return Stamp(
            sessionID: session.id,
            serviceDayID: serviceDayID,
            title: session.title,
            stampedAt: stampedAt,
            punctuality: punctuality,
            sealTier: judgment.sealTier,
            stampSeason: PunctualityJudgment.stampSeason(at: stampedAt),
            stampTimeOfDay: PunctualityJudgment.stampTimeOfDay(at: stampedAt),
            judgedEstimateMinutes: max(Int(judgment.judgedTotalSeconds.rounded()), 1) / 60,
            originalEstimateMinutes: max(session.estimatedSecondsAtStart, 0) / 60,
            reestimateTotalMinutes: reestimateTotal,
            actualMinutes: max(0, Int((session.accumulatedActiveSeconds / 60).rounded()))
        )
    }

    private static func mapOutcome(_ outcome: PunctualityJudgment.Outcome) -> ArrivalPunctuality {
        switch outcome {
        case .onTime: .onTime
        case .early: .early
        case .late: .late
        case .notApplicable: .notApplicable
        }
    }
}

extension TicketStampBundleAssembly {
    static func sessionInput(from session: WorkSession) -> SessionInput {
        SessionInput(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            outcome: session.outcome,
            arrivalStampedAt: session.arrivalStampedAt,
            title: session.ticket?.title ?? "切符",
            estimatedSecondsAtStart: session.estimatedSecondsAtStart,
            accumulatedActiveSeconds: session.accumulatedActiveSeconds,
            reestimates: session.reestimateEvents.map {
                ReestimateInput(
                    reestimateIndex: $0.reestimateIndex,
                    activeSeconds: $0.activeSeconds,
                    committedRemainingSeconds: $0.committedRemainingSeconds,
                    undoneAt: $0.undoneAt
                )
            }
        )
    }

    static func serviceDayInput(from day: ServiceDay) -> ServiceDayInput {
        ServiceDayInput(
            id: day.id,
            startedAt: day.startedAt,
            endedAt: day.endedAt,
            calendarDayKey: day.calendarDayKey
        )
    }
}
