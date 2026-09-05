//
//  CoachingEngineTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct CoachingEngineTests {
    @Test func heuristic_split_forLongEstimates() async {
        let engine = HeuristicCoachingEngine()
        let suggestion = await engine.suggestSplit(for: "資料作成", estimatedMinutes: 50)
        #expect(suggestion?.segments.count == 2)
        #expect(suggestion?.note?.contains("ヒューリスティック") == true)
    }

    @Test func heuristic_split_nilForShortEstimates() async {
        let engine = HeuristicCoachingEngine()
        let suggestion = await engine.suggestSplit(for: "メール", estimatedMinutes: 15)
        #expect(suggestion == nil)
    }

    @Test func heuristic_dailyReview_summarizesSessions() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "A", estimatedSeconds: 600)
        context.insert(ticket)
        let session = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        session.endedAt = .now
        session.outcome = .arrived
        session.accumulatedActiveSeconds = 600
        context.insert(session)
        try context.save()

        let engine = HeuristicCoachingEngine()
        let lines = await engine.checkInLines(title: "資料作成", estimatedMinutes: 30)
        #expect(lines == ["まだ『資料作成』？"])
    }
}
