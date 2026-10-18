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

    @Test func sealSampleAccessibility_usesLuxuryLabel() {
        #expect(
            PunctualityPresentation.sealSampleAccessibilityLabel(luxury: 1.0)
                == "かかっている判：発券時の見積もり"
        )
        #expect(
            PunctualityPresentation.sealSampleAccessibilityLabel(luxury: 0.72)
                == "かかっている判：走行前半の見積もり直し"
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

    @Test func homeMeterAccessibility_omitsSealWhenSignalOff() {
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: false,
                activeSeconds: 2_100,
                estimatedSecondsAtStart: 1_800,
                reestimates: []
            )
        )
        let label = PunctualityPresentation.homeMeterAccessibilityLabel(
            judgment: judgment,
            activeSeconds: 2_100,
            sealLuxury: 1.0
        )
        #expect(label == "ホームを過ぎました")
        #expect(!label.contains("かかっている判"))
    }

    @Test func ridingSealLuxury_hiddenWhenSignalOff() {
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: false,
                activeSeconds: 2_100,
                estimatedSecondsAtStart: 1_800,
                reestimates: []
            )
        )
        #expect(judgment.signal == .off)
        let luxury = PunctualityPresentation.ridingSealLuxury(
            judgment: judgment,
            reestimates: []
        )
        #expect(luxury == nil)
    }

    @Test func ridingSealLuxury_shownAfterReestimateMovesHome() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 600,
                committedRemainingSeconds: 1_200
            ),
        ]
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: false,
                activeSeconds: 800,
                estimatedSecondsAtStart: 1_800,
                reestimates: events
            )
        )
        #expect(judgment.signal == .green)
        let luxury = PunctualityPresentation.ridingSealLuxury(
            judgment: judgment,
            reestimates: events
        )
        #expect(luxury == 0.6)
    }

    @Test func actualProgressTenth_clampsToTen() {
        #expect(
            PunctualityPresentation.actualProgressTenth(
                answerActiveSeconds: 200,
                arrivalActiveSeconds: 500
            ) == 4
        )
        #expect(
            PunctualityPresentation.actualProgressTenth(
                answerActiveSeconds: 500,
                arrivalActiveSeconds: 500
            ) == 10
        )
        #expect(
            PunctualityPresentation.actualProgressTenth(
                answerActiveSeconds: 0,
                arrivalActiveSeconds: 500
            ) == 0
        )
    }

    @Test func actualProgressTenth_overtimeArrival_staysWithinRange() {
        let answer = 12 * 60.0
        let arrival = 52 * 60.0
        let tenth = PunctualityPresentation.actualProgressTenth(
            answerActiveSeconds: answer,
            arrivalActiveSeconds: arrival
        )
        #expect((0...10).contains(tenth))
        #expect(tenth == 2)
    }

    @Test func progressComparisonLine_matchesAnsweredShare() {
        let ticket = Ticket(title: "t", estimatedSeconds: 3_600)
        var session = WorkSession(
            startedAt: Date(timeIntervalSince1970: 0),
            estimatedSecondsAtStart: 3_600,
            ticket: ticket
        )
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
        #expect(line == "4割と答えた時点 → 実際は全体の4割")
    }

    @Test func rideLog_omitsReestimateRowWhenNone() {
        let ticket = Ticket(title: "t", estimatedSeconds: 1_800)
        let session = WorkSession(
            startedAt: .now,
            estimatedSecondsAtStart: 1_800,
            ticket: ticket
        )
        session.accumulatedActiveSeconds = 1_700
        let lines = PunctualityPresentation.rideLogLines(for: session).map(\.text)
        #expect(lines == ["最初の見積もり 30分", "実際 28分"])
    }
}
