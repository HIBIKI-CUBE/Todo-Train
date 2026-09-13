//
//  WeeklyReportTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct WeeklyReportTests {
  @Test func aggregate_countsSessionsInWeek() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let wednesday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 15))!

    let container = try AppModelContainer.make(inMemory: true)
    let context = ModelContext(container)
    let ticket = Ticket(title: "A", estimatedSeconds: 600)
    context.insert(ticket)

    let session = WorkSession(startedAt: wednesday, estimatedSecondsAtStart: 600, ticket: ticket)
    session.endedAt = wednesday.addingTimeInterval(300)
    session.outcome = .arrived
    session.accumulatedActiveSeconds = 300
    context.insert(session)
    try context.save()

    let aggregate = WeeklyReport.aggregate(
      sessions: [session],
      weekContaining: wednesday,
      calendar: calendar
    )
    #expect(aggregate.arrived == 1)
    #expect(aggregate.focusMinutes == 5)
  }

  @Test func groupByWeek_ordersNewestFirst() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let week1 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
    let week2 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 19))!

    let container = try AppModelContainer.make(inMemory: true)
    let context = ModelContext(container)

    func makeEnded(at date: Date) -> WorkSession {
      let ticket = Ticket(title: "T", estimatedSeconds: 60)
      context.insert(ticket)
      let session = WorkSession(startedAt: date, estimatedSecondsAtStart: 60, ticket: ticket)
      session.endedAt = date
      session.outcome = .arrived
      context.insert(session)
      return session
    }

    let older = makeEnded(at: week1)
    let newer = makeEnded(at: week2)
    try context.save()

    let groups = WeeklyReport.groupByWeek(sessions: [older, newer], calendar: calendar)
    #expect(groups.count == 2)
    #expect(groups[0].weekStart > groups[1].weekStart)
  }
}
