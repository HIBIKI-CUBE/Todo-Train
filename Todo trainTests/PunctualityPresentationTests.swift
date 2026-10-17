//
//  PunctualityPresentationTests.swift
//  Todo trainTests
//

import Foundation
import Testing
import TodoTrainSync
@testable import Todo_train

@Suite("Punctuality presentation")
struct PunctualityPresentationTests {
    @Test func firstTimeTipKeys_areStable() {
        #expect(PunctualityFirstTimeTips.homeStorageKey == "punctuality.tip.home")
        #expect(PunctualityFirstTimeTips.sealStorageKey == "punctuality.tip.seal")
    }

    @Test func signalAccessibility_greenMinutes() {
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: false,
                activeSeconds: 500,
                estimatedSecondsAtStart: 1_800,
                reestimates: []
            )
        )
        let label = PunctualityPresentation.signalAccessibilityLabel(
            judgment: judgment,
            activeSeconds: 500
        )
        #expect(label.hasPrefix("ホームまであと"))
    }

    @Test func signalAccessibility_yellowInsideHome() {
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: false,
                activeSeconds: 1_700,
                estimatedSecondsAtStart: 1_800,
                reestimates: []
            )
        )
        #expect(
            PunctualityPresentation.signalAccessibilityLabel(
                judgment: judgment,
                activeSeconds: 1_700
            ) == "ホームの中"
        )
    }

    @Test func sealSampleAccessibility_usesJudgedSourceLabel() {
        #expect(
            PunctualityPresentation.sealSampleAccessibilityLabel(tier: .ticketing)
                == "かかっている判：発券時の見積もり"
        )
    }

    @Test func stampAccessibility_includesCornerSealForOnTime() {
        #expect(
            PunctualityPresentation.stampAccessibilityLabel(
                punctuality: .onTime,
                includesCornerSeal: true
            ) == "定時の角判の印"
        )
    }

    @Test func progressComparisonLine_matchesAnsweredShare() {
        let ticket = Ticket(title: "t", estimatedSeconds: 3_600)
        var session = WorkSession(
            startedAt: Date(timeIntervalSince1970: 0),
            estimatedSecondsAtStart: 3_600,
            ticket: ticket
        )
        session.accumulatedActiveSeconds = 500
        session.reestimateEvents = [
            ReestimateEventRecord(
                id: UUID(),
                reestimateIndex: 1,
                trigger: .manual,
                surface: .iphonePortrait,
                input: .touch,
                promptId: "p",
                mode: .progress,
                committedAt: Date(timeIntervalSince1970: 100),
                activeSeconds: 200,
                overrunSeconds: 0,
                progressAnswer: 0.4,
                committedRemainingSeconds: 1_800,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false,
                undoneAt: nil,
                remoteWillExtendReceived: false
            ),
        ]
        session.accumulatedActiveSeconds = 500
        let line = PunctualityPresentation.progressComparisonLine(for: session)
        #expect(line == "4割と答えた時点 → 実際は全体の10割")
    }
}
