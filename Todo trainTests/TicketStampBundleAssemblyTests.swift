//
//  TicketStampBundleAssemblyTests.swift
//  Todo trainTests
//

import Foundation
import Testing
import TodoTrainSync
@testable import Todo_train

@Suite("Ticket stamp bundle assembly")
struct TicketStampBundleAssemblyTests {
    private let dayA = UUID()
    private let dayB = UUID()
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func serviceDays() -> [TicketStampBundleAssembly.ServiceDayInput] {
        [
            TicketStampBundleAssembly.ServiceDayInput(
                id: dayA,
                startedAt: base,
                endedAt: base.addingTimeInterval(86_400),
                calendarDayKey: "2026-01-01"
            ),
            TicketStampBundleAssembly.ServiceDayInput(
                id: dayB,
                startedAt: base.addingTimeInterval(86_400),
                endedAt: nil,
                calendarDayKey: "2026-01-02"
            ),
        ]
    }

    private func session(
        startedAt: Date,
        id: UUID = UUID(),
        outcome: SessionOutcome? = .arrived,
        stampedAt: Date? = nil,
        title: String = "切符",
        estimate: Int = 30 * 60,
        active: TimeInterval = 30 * 60,
        reestimates: [TicketStampBundleAssembly.ReestimateInput] = []
    ) -> TicketStampBundleAssembly.SessionInput {
        TicketStampBundleAssembly.SessionInput(
            id: id,
            startedAt: startedAt,
            endedAt: stampedAt,
            outcome: outcome,
            arrivalStampedAt: stampedAt,
            title: title,
            estimatedSecondsAtStart: estimate,
            accumulatedActiveSeconds: active,
            reestimates: reestimates
        )
    }

    @Test func excludesPartialAbandonAndUnstamped() {
        let sessions = [
            session(startedAt: base, stampedAt: base.addingTimeInterval(100)),
            session(
                startedAt: base.addingTimeInterval(200),
                outcome: .partialDisembark,
                stampedAt: base.addingTimeInterval(300)
            ),
            session(
                startedAt: base.addingTimeInterval(400),
                outcome: .abandoned,
                stampedAt: base.addingTimeInterval(500)
            ),
            session(
                startedAt: base.addingTimeInterval(600),
                outcome: .arrived,
                stampedAt: nil
            ),
        ]
        let bundles = TicketStampBundleAssembly.buildDayBundles(sessions: sessions, serviceDays: serviceDays())
        #expect(bundles.count == 1)
        #expect(bundles[0].stamps.count == 1)
    }

    @Test func groupsByServiceDayContainingDeparture() {
        let cross = session(
            startedAt: base.addingTimeInterval(86_000),
            stampedAt: base.addingTimeInterval(87_000)
        )
        let bundles = TicketStampBundleAssembly.buildDayBundles(
            sessions: [cross],
            serviceDays: serviceDays()
        )
        #expect(bundles.count == 1)
        #expect(bundles[0].serviceDayID == dayA)
    }

    @Test func interruptionStampIncluded() {
        let interrupt = session(
            startedAt: base.addingTimeInterval(120),
            stampedAt: base.addingTimeInterval(900),
            title: "割り込み"
        )
        let bundles = TicketStampBundleAssembly.buildDayBundles(
            sessions: [interrupt],
            serviceDays: serviceDays()
        )
        #expect(bundles[0].stamps.count == 1)
        #expect(bundles[0].stamps[0].title == "割り込み")
    }

    @Test func sealTierMatchesJudge() {
        let re = TicketStampBundleAssembly.ReestimateInput(
            reestimateIndex: 1,
            activeSeconds: 10 * 60,
            committedRemainingSeconds: 40 * 60,
            undoneAt: nil
        )
        let ride = session(
            startedAt: base.addingTimeInterval(60),
            stampedAt: base.addingTimeInterval(3_100),
            active: 50 * 60,
            reestimates: [re]
        )
        let bundles = TicketStampBundleAssembly.buildDayBundles(sessions: [ride], serviceDays: serviceDays())
        let stamp = bundles.first?.stamps.first
        #expect(stamp != nil)
        guard let stamp else { return }
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: true,
                activeSeconds: ride.accumulatedActiveSeconds,
                estimatedSecondsAtStart: ride.estimatedSecondsAtStart,
                reestimates: [
                    PunctualityJudgment.ReestimateCommit(
                        reestimateIndex: 1,
                        activeSeconds: 10 * 60,
                        committedRemainingSeconds: 40 * 60
                    ),
                ]
            )
        )
        #expect(stamp.sealTier == judgment.sealTier)
        #expect(stamp.punctuality == .onTime)
    }

    @Test func stampOrnamentStableForSameInstant() {
        let instant = base.addingTimeInterval(500)
        let a = session(startedAt: base, stampedAt: instant)
        let b = session(startedAt: base.addingTimeInterval(10), stampedAt: instant)
        let bundles = TicketStampBundleAssembly.buildDayBundles(sessions: [a, b], serviceDays: serviceDays())
        let stamps = bundles.first?.stamps
        #expect(stamps != nil)
        guard let stamps else { return }
        #expect(stamps[0].stampSeason == stamps[1].stampSeason)
        #expect(stamps[0].stampTimeOfDay == stamps[1].stampTimeOfDay)
    }

    @Test func flattenMarksDayBoundaries() {
        let sessions = [
            session(startedAt: base, stampedAt: base.addingTimeInterval(100)),
            session(startedAt: base.addingTimeInterval(200), stampedAt: base.addingTimeInterval(300)),
            session(
                startedAt: base.addingTimeInterval(86_400 + 10),
                stampedAt: base.addingTimeInterval(86_400 + 100)
            ),
        ]
        let flat = TicketStampBundleAssembly.flatten(
            TicketStampBundleAssembly.buildDayBundles(sessions: sessions, serviceDays: serviceDays())
        )
        #expect(flat.count == 3)
        #expect(flat[0].dayBoundaryBefore)
        #expect(!flat[1].dayBoundaryBefore)
        #expect(flat[2].dayBoundaryBefore)
    }
}
