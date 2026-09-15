//
//  TimetableFitTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TimetableFitTests {
    @Test func nextBlock_skipsCancelledAndPast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = block(id: 1, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800))
        let cancelled = block(id: 2, start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800), cancelled: true)
        let next = block(id: 3, start: now.addingTimeInterval(1200), end: now.addingTimeInterval(2400))
        let later = block(id: 4, start: now.addingTimeInterval(3600), end: now.addingTimeInterval(5400))
        #expect(TimetableFit.nextBlock(in: [past, cancelled, later, next], now: now)?.id == next.id)
    }

    @Test func markMinutes_onlyOnSixtyMinuteTrack() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TimetableFit.markMinutes(now: now, nextStart: now.addingTimeInterval(20 * 60)) == 20)
        #expect(TimetableFit.markMinutes(now: now, nextStart: now.addingTimeInterval(60 * 60)) == 60)
        #expect(TimetableFit.markMinutes(now: now, nextStart: now.addingTimeInterval(61 * 60)) == nil)
        #expect(TimetableFit.markMinutes(now: now, nextStart: now.addingTimeInterval(30)) == nil)
        #expect(TimetableFit.markMinutes(now: now, nextStart: nil) == nil)
    }

    @Test func nextDeadline_isEarlierOfBudgetAndBlock() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let budget = now.addingTimeInterval(45 * 60)
        let block = now.addingTimeInterval(20 * 60)
        #expect(TimetableFit.nextDeadline(budgetEnd: budget, nextBlockStart: block) == block)
        #expect(TimetableFit.nextDeadline(budgetEnd: budget, nextBlockStart: nil) == budget)
        #expect(TimetableFit.nextDeadline(budgetEnd: nil, nextBlockStart: block) == block)
        #expect(TimetableFit.nextDeadline(budgetEnd: nil, nextBlockStart: nil) == nil)
    }

    private func block(
        id: Int,
        start: Date,
        end: Date,
        cancelled: Bool = false
    ) -> TimetableFit.Block {
        TimetableFit.Block(
            id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(id)")!,
            title: "B\(id)",
            startsAt: start,
            endsAt: end,
            isCancelled: cancelled
        )
    }
}
