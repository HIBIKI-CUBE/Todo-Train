//
//  EstimateHeuristicTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct EstimateHeuristicTests {
    @Test func medianSeconds_oddCount() {
        let median = EstimateHeuristic.medianSeconds([300, 900, 600])
        #expect(median == 600)
    }

    @Test func medianSeconds_evenCount() {
        let median = EstimateHeuristic.medianSeconds([300, 600, 900, 1200])
        #expect(median == 750)
    }

    @Test func medianSeconds_emptyIsNil() {
        #expect(EstimateHeuristic.medianSeconds([]) == nil)
    }

    @Test func snapToPresetMinutes_roundsToNearest() {
        #expect(EstimateHeuristic.snapToPresetMinutes(22 * 60) == 20)
        #expect(EstimateHeuristic.snapToPresetMinutes(27 * 60) == 30)
        #expect(EstimateHeuristic.snapToPresetMinutes(5 * 60) == 5)
        #expect(EstimateHeuristic.snapToPresetMinutes(60 * 60) == 60)
    }

    @Test func snapToPresetMinutes_tiePrefersLower() {
        // Midpoint between 20 and 30 is 25 → equal distance; prefer lower (20).
        #expect(EstimateHeuristic.snapToPresetMinutes(25 * 60) == 20)
    }

    @Test func suggestion_requiresMinimumSamples() {
        let two = [TimeInterval(600), 900]
        #expect(EstimateHeuristic.suggestion(from: two) == nil)

        let three = [TimeInterval(600), 900, 1200]
        let suggestion = EstimateHeuristic.suggestion(from: three)
        #expect(suggestion?.sampleCount == 3)
        #expect(suggestion?.minutes == 15) // median 900s = 15m
    }

    @Test func caption_format() {
        #expect(
            EstimateHeuristic.caption(minutes: 20, sampleCount: 5)
                == "過去の中央値 約20分（5件）"
        )
    }

    @Test func arrivedRides_dropsImmediateArrivalButKeepsEarlyFinish() {
        let ticket = Ticket(title: "T", estimatedSeconds: 30 * 60)
        let immediate = ride(ticket: ticket, active: 8, estimate: 30 * 60)
        let almostMinute = ride(ticket: ticket, active: 59, estimate: 30 * 60)
        let justRode = ride(ticket: ticket, active: 60, estimate: 30 * 60)
        let earlyFinish = ride(ticket: ticket, active: 8 * 60, estimate: 30 * 60)

        let samples = EstimateHeuristic.arrivedSamples(
            from: [immediate, almostMinute, justRode, earlyFinish],
            matchingAnyTagIDs: nil
        )
        #expect(samples == [60, 8 * 60])
    }

    private func ride(ticket: Ticket, active: TimeInterval, estimate: Int) -> WorkSession {
        let session = WorkSession(startedAt: .now, estimatedSecondsAtStart: estimate, ticket: ticket)
        session.endedAt = .now
        session.outcome = .arrived
        session.accumulatedActiveSeconds = active
        return session
    }
}
