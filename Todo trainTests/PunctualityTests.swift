//
//  PunctualityTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct PunctualityTests {
    @Test func slack_usesFifteenPercentWithFloor() {
        #expect(Punctuality.slack(estimateSeconds: 300) == 45) // 5分: floor
        #expect(Punctuality.slack(estimateSeconds: 600) == 90) // 10分: 15%
        #expect(Punctuality.slack(estimateSeconds: 1800) == 270) // 30分: 15%
        #expect(Punctuality.slack(estimateSeconds: 3600) == 540) // 60分: 15%
    }

    @Test func classify_onTime_nearEstimate() {
        #expect(
            Punctuality.classify(
                outcome: .arrived,
                elapsedSeconds: 290,
                estimateSeconds: 300,
                overtimeResolution: nil
            ) == .onTime
        )
        #expect(
            Punctuality.classify(
                outcome: .arrived,
                elapsedSeconds: 300,
                estimateSeconds: 300,
                overtimeResolution: nil
            ) == .onTime
        )
        #expect(
            Punctuality.classify(
                outcome: .arrived,
                elapsedSeconds: 1_560,
                estimateSeconds: 1_800,
                overtimeResolution: nil
            ) == .onTime
        )
    }

    @Test func classify_early_isNotCelebrated() {
        // Immediate tap / padded estimate → 早着. No 定時.
        #expect(
            Punctuality.classify(
                outcome: .arrived,
                elapsedSeconds: 5,
                estimateSeconds: 300,
                overtimeResolution: nil
            ) == .early
        )
        #expect(
            Punctuality.classify(
                outcome: .arrived,
                elapsedSeconds: 1_200,
                estimateSeconds: 1_800,
                overtimeResolution: nil
            ) == .early
        )
    }

    @Test func classify_late_whenOvertimeOrPastEstimate() {
        #expect(
            Punctuality.classify(
                outcome: .arrived,
                elapsedSeconds: 280,
                estimateSeconds: 300,
                overtimeResolution: .justFinished
            ) == .late
        )
        #expect(
            Punctuality.classify(
                outcome: .arrived,
                elapsedSeconds: 400,
                estimateSeconds: 300,
                overtimeResolution: nil
            ) == .late
        )
    }

    @Test func classify_notApplicable_unlessArrived() {
        #expect(
            Punctuality.classify(
                outcome: .partialDisembark,
                elapsedSeconds: 300,
                estimateSeconds: 300,
                overtimeResolution: nil
            ) == .notApplicable
        )
        #expect(
            Punctuality.classify(
                outcome: .abandoned,
                elapsedSeconds: 300,
                estimateSeconds: 300,
                overtimeResolution: nil
            ) == .notApplicable
        )
        #expect(
            Punctuality.classify(
                outcome: nil,
                elapsedSeconds: 300,
                estimateSeconds: 300,
                overtimeResolution: nil
            ) == .notApplicable
        )
    }

    @Test func classify_usesOriginalEstimate_notExtendedBudget() {
        // 延長して予算を足しても、当初 30 分より長く乗れば定時ではない。
        #expect(
            Punctuality.classify(
                outcome: .arrived,
                elapsedSeconds: 2_100,
                estimateSeconds: 1_800,
                overtimeResolution: nil
            ) == .late
        )
    }

    @Test func isOnTimeService_requiresEveryArrivalOnTime() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 600)
        context.insert(ticket)

        let onTime = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        onTime.endedAt = .now
        onTime.outcome = .arrived
        onTime.accumulatedActiveSeconds = 560
        context.insert(onTime)

        #expect(Punctuality.isOnTimeService(arrivedSessions: [onTime]))

        let early = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        early.endedAt = .now
        early.outcome = .arrived
        early.accumulatedActiveSeconds = 60
        context.insert(early)

        #expect(!Punctuality.isOnTimeService(arrivedSessions: [onTime, early]))
        #expect(!Punctuality.isOnTimeService(arrivedSessions: []))
    }

    @Test func isOnTimeService_ignoresNonArrivals() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 600)
        context.insert(ticket)

        let arrived = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        arrived.endedAt = .now
        arrived.outcome = .arrived
        arrived.accumulatedActiveSeconds = 580

        let abandoned = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        abandoned.endedAt = .now
        abandoned.outcome = .abandoned
        abandoned.accumulatedActiveSeconds = 10

        context.insert(arrived)
        context.insert(abandoned)

        #expect(Punctuality.isOnTimeService(arrivedSessions: [arrived, abandoned]))
    }

    @Test func displayLabel_usesTeijiForOnTimeArrival() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 600)
        context.insert(ticket)

        let session = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        session.endedAt = .now
        session.outcome = .arrived
        session.accumulatedActiveSeconds = 590
        context.insert(session)

        #expect(Punctuality.displayLabel(for: session) == "定時")
    }

    @Test func displayLabel_earlyArrivalStaysArrived() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 600)
        context.insert(ticket)

        let session = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        session.endedAt = .now
        session.outcome = .arrived
        session.accumulatedActiveSeconds = 30
        context.insert(session)

        #expect(Punctuality.displayLabel(for: session) == "到着")
    }

    @Test func durationCaption_matchesHistoryStyle() {
        #expect(
            Punctuality.durationCaption(estimateSeconds: 1_500, actualSeconds: 1_440)
                == "見積もり 25分 · 実績 24分"
        )
    }

    @Test func presentation_isBriefNotAScoreScreen() {
        #expect(PunctualityMoment.presentationMilliseconds <= 900)
        #expect(PunctualityMoment.presentationMilliseconds >= 650)
    }
}
