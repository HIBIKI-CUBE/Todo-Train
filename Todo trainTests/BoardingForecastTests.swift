//
//  BoardingForecastTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct BoardingForecastTests {
    @Test func scheduledArrival_isNowPlusEstimate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 16, minute: 12))!
        let snapshot = BoardingForecast.make(
            now: now,
            estimatedSeconds: 30 * 60,
            sessions: [],
            matchingAnyTagIDs: nil
        )
        #expect(snapshot.scheduledMinutes == 30)
        #expect(snapshot.scheduledArrival == now.addingTimeInterval(30 * 60))
        #expect(snapshot.hasPrediction == false)
        #expect(snapshot.sampleCount == 0)
        #expect(
            BoardingForecast.timeString(from: snapshot.scheduledArrival, timeZone: calendar.timeZone)
                == "16:42"
        )
        #expect(
            BoardingForecast.predictedTimeString(
                from: snapshot.scheduledArrival,
                timeZone: calendar.timeZone
            ) == "約 16:42"
        )
    }

    @Test func prediction_requiresMinimumSamplesAndDoesNotSnap() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 20 * 60)
        context.insert(ticket)

        let two = [
            arrived(context, ticket: ticket, active: 22 * 60),
            arrived(context, ticket: ticket, active: 24 * 60),
        ]
        let short = BoardingForecast.make(
            now: .now,
            estimatedSeconds: ticket.estimatedSeconds,
            sessions: two,
            matchingAnyTagIDs: nil
        )
        #expect(short.hasPrediction == false)
        #expect(short.sampleCount == 2)

        let three = two + [arrived(context, ticket: ticket, active: 23 * 60)]
        let snapshot = BoardingForecast.make(
            now: .now,
            estimatedSeconds: ticket.estimatedSeconds,
            sessions: three,
            matchingAnyTagIDs: nil
        )
        #expect(snapshot.hasPrediction)
        #expect(snapshot.predictedMinutes == 23)
        #expect(snapshot.sampleCount == 3)
        #expect(snapshot.predictedScaleMinutes == 23)
    }

    @Test func prediction_ignoresNonArrivals() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 15 * 60)
        context.insert(ticket)

        let sessions = [
            arrived(context, ticket: ticket, active: 18 * 60),
            arrived(context, ticket: ticket, active: 20 * 60),
            arrived(context, ticket: ticket, active: 22 * 60),
            abandoned(context, ticket: ticket, active: 60 * 60),
        ]
        let snapshot = BoardingForecast.make(
            now: .now,
            estimatedSeconds: ticket.estimatedSeconds,
            sessions: sessions,
            matchingAnyTagIDs: nil
        )
        #expect(snapshot.predictedMinutes == 20)
        #expect(snapshot.sampleCount == 3)
    }

    @Test func prediction_filtersByTicketTags() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let work = Tag(name: "仕事", sortOrder: 0)
        let home = Tag(name: "家", sortOrder: 1)
        let workTicket = Ticket(title: "仕事", estimatedSeconds: 20 * 60)
        let homeTicket = Ticket(title: "家", estimatedSeconds: 10 * 60)
        context.insert(work)
        context.insert(home)
        context.insert(workTicket)
        context.insert(homeTicket)
        workTicket.tags = [work]
        homeTicket.tags = [home]
        try context.save()

        let sessions = [
            arrived(context, ticket: workTicket, active: 30 * 60),
            arrived(context, ticket: workTicket, active: 32 * 60),
            arrived(context, ticket: workTicket, active: 34 * 60),
            arrived(context, ticket: homeTicket, active: 8 * 60),
            arrived(context, ticket: homeTicket, active: 9 * 60),
            arrived(context, ticket: homeTicket, active: 10 * 60),
        ]
        let snapshot = BoardingForecast.make(
            now: .now,
            ticket: workTicket,
            sessions: sessions
        )
        #expect(snapshot.predictedMinutes == 32)
        #expect(snapshot.sampleCount == 3)
    }

    @Test func untagged_usesAllArrivals() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let tagged = Tag(name: "仕事", sortOrder: 0)
        let taggedTicket = Ticket(title: "仕事", estimatedSeconds: 20 * 60)
        let plain = Ticket(title: "無題", estimatedSeconds: 30 * 60)
        context.insert(tagged)
        context.insert(taggedTicket)
        context.insert(plain)
        taggedTicket.tags = [tagged]
        try context.save()

        let sessions = [
            arrived(context, ticket: taggedTicket, active: 10 * 60),
            arrived(context, ticket: taggedTicket, active: 12 * 60),
            arrived(context, ticket: taggedTicket, active: 14 * 60),
        ]
        #expect(BoardingForecast.tagFilter(for: plain) == nil)
        let snapshot = BoardingForecast.make(now: .now, ticket: plain, sessions: sessions)
        #expect(snapshot.predictedMinutes == 12)
        #expect(snapshot.sampleCount == 3)
    }

    @Test func prediction_prefersCurrentHourBandWhenSampled() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "資料", estimatedSeconds: 20 * 60)
        context.insert(ticket)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 20))!

        let sessions = [
            arrived(context, ticket: ticket, active: 10 * 60, at: morning),
            arrived(context, ticket: ticket, active: 12 * 60, at: morning),
            arrived(context, ticket: ticket, active: 14 * 60, at: morning),
            arrived(context, ticket: ticket, active: 40 * 60, at: evening),
            arrived(context, ticket: ticket, active: 42 * 60, at: evening),
            arrived(context, ticket: ticket, active: 44 * 60, at: evening),
        ]
        let atNight = BoardingForecast.make(
            now: evening,
            estimatedSeconds: ticket.estimatedSeconds,
            sessions: sessions,
            matchingAnyTagIDs: nil,
            calendar: calendar
        )
        #expect(atNight.predictedMinutes == 42)
        #expect(atNight.sampleCount == 3)

        let atMorning = BoardingForecast.make(
            now: morning,
            estimatedSeconds: ticket.estimatedSeconds,
            sessions: sessions,
            matchingAnyTagIDs: nil,
            calendar: calendar
        )
        #expect(atMorning.predictedMinutes == 12)
    }

    @Test func scaleMinutes_clampsPredictionAboveSixty() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples: [TimeInterval] = [70 * 60, 80 * 60, 90 * 60]
        let predicted = BoardingForecast.predictedDuration(from: samples)
        #expect(predicted?.minutes == 80)
        let snapshot = BoardingForecast.make(
            now: now,
            estimatedSeconds: 60 * 60,
            sessions: [],
            matchingAnyTagIDs: nil
        )
        #expect(snapshot.scheduledScaleMinutes == 60)
        #expect(TicketDurationScale.clampedMinutes(80) == 60)
        #expect(TicketDurationScale.unitFraction(minutes: 30) == 0.5)
    }

    @Test func predictedCopy_marksForecast() {
        #expect(BoardingForecast.predictedCaption(minutes: 38, sampleCount: 5) == "予測 約38分 · 参考5件")
        #expect(BoardingForecast.durationLabel(minutes: 30) == "30分")
        #expect(BoardingForecast.predictedDurationLabel(minutes: 12) == "約12分")
        #expect(BoardingForecast.scheduledHeadline == "予定の到着")
        #expect(BoardingForecast.predictedHeadline == "予測の到着")
    }

    @Test func prediction_ignoresImmediateArrivalButKeepsEarlyFinish() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 30 * 60)
        context.insert(ticket)

        let sessions = [
            arrived(context, ticket: ticket, active: 5),
            arrived(context, ticket: ticket, active: 12),
            arrived(context, ticket: ticket, active: 20),
            arrived(context, ticket: ticket, active: 8 * 60),
            arrived(context, ticket: ticket, active: 9 * 60),
            arrived(context, ticket: ticket, active: 10 * 60),
        ]
        let snapshot = BoardingForecast.make(
            now: .now,
            estimatedSeconds: ticket.estimatedSeconds,
            sessions: sessions,
            matchingAnyTagIDs: nil
        )
        #expect(snapshot.hasPrediction)
        #expect(snapshot.predictedMinutes == 9)
        #expect(snapshot.sampleCount == 3)
    }

    @Test func evenMedian_roundsToNearestMinute() {
        let predicted = BoardingForecast.predictedDuration(from: [10 * 60, 12 * 60, 13 * 60, 15 * 60])
        #expect(predicted?.minutes == 13)
    }

    @Test func withPredictedMinutes_replacesClock() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let base = BoardingForecast.Snapshot(
            scheduledArrival: now.addingTimeInterval(30 * 60),
            scheduledMinutes: 30,
            predictedArrival: now.addingTimeInterval(32 * 60),
            predictedMinutes: 32,
            sampleCount: 4
        )
        let refined = base.withPredictedMinutes(40, now: now)
        #expect(refined.predictedMinutes == 40)
        #expect(refined.predictedArrival == now.addingTimeInterval(40 * 60))
    }

    private func arrived(
        _ context: ModelContext,
        ticket: Ticket,
        active: TimeInterval,
        at startedAt: Date = .now
    ) -> WorkSession {
        let session = WorkSession(
            startedAt: startedAt,
            estimatedSecondsAtStart: ticket.estimatedSeconds,
            ticket: ticket
        )
        session.endedAt = startedAt
        session.outcome = .arrived
        session.accumulatedActiveSeconds = active
        context.insert(session)
        return session
    }

    private func abandoned(
        _ context: ModelContext,
        ticket: Ticket,
        active: TimeInterval
    ) -> WorkSession {
        let session = WorkSession(startedAt: .now, estimatedSecondsAtStart: ticket.estimatedSeconds, ticket: ticket)
        session.endedAt = .now
        session.outcome = .abandoned
        session.accumulatedActiveSeconds = active
        context.insert(session)
        return session
    }
}
