//
//  HistoryStatsTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct HistoryStatsTests {
    @Test func dayKey_formatsCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC-ish
        let key = HistoryStats.dayKey(for: date, calendar: calendar)
        #expect(key.count == 10)
        #expect(key.contains("-"))
    }

    @Test func aggregate_sumsFocusAndCountsOutcomes() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 600)
        context.insert(ticket)

        let a = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        a.accumulatedActiveSeconds = 300
        a.endedAt = .now
        a.outcome = .arrived

        let b = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        b.accumulatedActiveSeconds = 120
        b.endedAt = .now
        b.outcome = .partialDisembark

        let c = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        c.accumulatedActiveSeconds = 60
        c.endedAt = .now
        c.outcome = .abandoned

        context.insert(a)
        context.insert(b)
        context.insert(c)

        let stats = HistoryStats.aggregate(sessions: [a, b, c])
        #expect(stats.focusSeconds == 480)
        #expect(stats.arrived == 1)
        #expect(stats.partialDisembark == 1)
        #expect(stats.abandoned == 1)
        #expect(stats.focusMinutes == 8)
    }

    @Test func groupByDay_ordersNewestFirst() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 600)
        context.insert(ticket)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let day1 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9))!

        let older = WorkSession(startedAt: day1, estimatedSecondsAtStart: 600, ticket: ticket)
        older.endedAt = day1
        older.outcome = .arrived
        older.accumulatedActiveSeconds = 100

        let newer = WorkSession(startedAt: day2, estimatedSecondsAtStart: 600, ticket: ticket)
        newer.endedAt = day2
        newer.outcome = .arrived
        newer.accumulatedActiveSeconds = 200

        context.insert(older)
        context.insert(newer)

        let groups = HistoryStats.groupByDay(sessions: [older, newer], calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups[0].dayKey == HistoryStats.dayKey(for: day2, calendar: calendar))
        #expect(groups[0].sessions.first?.id == newer.id)
        #expect(groups[1].sessions.first?.id == older.id)
    }

    @Test func dateFromDayKey_roundTrips() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!
        let key = HistoryStats.dayKey(for: date, calendar: calendar)
        #expect(key == "2026-09-08")
        let parsed = HistoryStats.date(from: key, calendar: calendar)
        #expect(parsed == date)
        #expect(HistoryStats.date(from: "nope") == nil)
    }

    @Test func weekDays_coverSevenDaysFromCalendarWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!
        let days = HistoryStats.weekDays(containing: tuesday, calendar: calendar)
        #expect(days.count == 7)
        #expect(calendar.component(.day, from: days[0]) == 6)
        #expect(calendar.component(.day, from: days[6]) == 12)
        #expect(calendar.isDate(days[2], inSameDayAs: tuesday))
    }
}
