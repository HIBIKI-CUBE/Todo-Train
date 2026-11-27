import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct WholeSecondSessionTests {
    @Test func recordFloorsStartPauseAndResume() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            now: Date(timeIntervalSince1970: 1_700_000_000.4)
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)

        let session = try #require(manager.activeSession)
        #expect(session.startedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(session.segmentStartedAt == Date(timeIntervalSince1970: 1_700_000_000))

        clock.advance(by: 30.8)
        try manager.pause()
        #expect(session.pausedAt == Date(timeIntervalSince1970: 1_700_000_031))
        #expect(session.accumulatedActiveSeconds == 31)
        #expect(session.pauses.first?.startedAt == Date(timeIntervalSince1970: 1_700_000_031))

        clock.advance(by: 10.9)
        try manager.resume()
        #expect(session.pausedAt == nil)
        #expect(session.segmentStartedAt == Date(timeIntervalSince1970: 1_700_000_042))
        #expect(session.pauses.first?.endedAt == Date(timeIntervalSince1970: 1_700_000_042))
        #expect(session.accumulatedActiveSeconds == 31)
    }

    @Test func storedFractionFloorsWhenRemainingIsRead() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let ticket = Ticket(title: "古い", estimatedSeconds: 100)
        context.insert(ticket)
        let session = WorkSession(
            startedAt: Date(timeIntervalSince1970: 1_000),
            estimatedSecondsAtStart: 100,
            ticket: ticket
        )
        session.startedAt = Date(timeIntervalSince1970: 1_000.8)
        session.segmentStartedAt = Date(timeIntervalSince1970: 1_000.8)
        session.accumulatedActiveSeconds = 0
        context.insert(session)

        let now = Date(timeIntervalSince1970: 1_060.4)
        let remaining = session.remainingSeconds(at: now)
        #expect(abs(remaining - 39.6) < 0.000_1)
        #expect(WholeSecond.countdownSeconds(remaining) == 40)
        #expect(CockpitFormat.timerLabel(remaining: 59.4) == "1:00")
        #expect(CockpitFormat.timerLabel(remaining: remaining) == "0:40")
        #expect(CockpitFormat.timerLabel(remaining: 0) == "0:00")
        #expect(CockpitFormat.timerLabel(remaining: 0.4) == "0:01")
        #expect(CockpitFormat.timerLabel(remaining: 0.5) == "0:01")
        #expect(CockpitFormat.timerLabel(remaining: 0.999) == "0:01")

        let snap = CompanionSnapBuilding.snap(
            rev: 1,
            phase: .running,
            session: session,
            now: now,
            serviceActive: true,
            cabinEnabled: true
        )
        #expect(snap.startedAt == 1_000)
        #expect(snap.pausedAccumulated == 0)
        #expect(snap.remainingSeconds(at: WholeSecond.unix(now)) == 40)
    }

    @Test func pausedFractionAgreesWithSnap() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let ticket = Ticket(title: "停車", estimatedSeconds: 100)
        context.insert(ticket)
        let session = WorkSession(
            startedAt: Date(timeIntervalSince1970: 1_000),
            estimatedSecondsAtStart: 100,
            ticket: ticket
        )
        session.startedAt = Date(timeIntervalSince1970: 1_000.8)
        session.segmentStartedAt = nil
        session.pausedAt = Date(timeIntervalSince1970: 2_000.7)
        session.accumulatedActiveSeconds = 10.9
        context.insert(session)

        let now = Date(timeIntervalSince1970: 2_500.4)
        #expect(session.elapsedSeconds(at: now) == 10)
        #expect(WholeSecond.countdownSeconds(session.remainingSeconds(at: now)) == 90)

        let snap = CompanionSnapBuilding.snap(
            rev: 1,
            phase: .paused,
            session: session,
            now: now,
            serviceActive: true,
            cabinEnabled: true
        )
        #expect(snap.startedAt == 1_000)
        #expect(snap.pausedAt == 2_000)
        #expect(snap.remainingSeconds(at: WholeSecond.unix(now)) == 90)
    }

    @Test func liveActivityDeadlineLandsOnAWholeSecond() throws {
        let live = InMemoryLiveActivityManager()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            now: Date(timeIntervalSince1970: 1_700_000_000.4),
            liveActivityManager: live
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "LA", seconds: 600)
        try manager.board(ticket: ticket)
        let session = try #require(manager.activeSession)

        clock.advance(by: 10)
        manager.refreshLiveActivity(for: session, now: clock.now)
        let running = try #require(live.current?.deadline)
        #expect(running == Date(timeIntervalSince1970: 1_700_000_600))
        #expect(running.timeIntervalSince1970 == running.timeIntervalSince1970.rounded(.down))

        try manager.pause()
        manager.refreshLiveActivity(for: session, now: clock.now)
        let paused = try #require(live.current?.deadline)
        #expect(paused.timeIntervalSince1970 == paused.timeIntervalSince1970.rounded(.down))
        #expect(live.current?.isPaused == true)
    }

    @Test func nextBlockInstantsFloor() {
        let starts = Date(timeIntervalSince1970: 1_768_000_400.8)
        let ends = Date(timeIntervalSince1970: 1_768_001_000.2)
        #expect(WholeSecond.unix(starts) == 1_768_000_400)
        #expect(WholeSecond.unix(ends) == 1_768_001_000)
    }
}
