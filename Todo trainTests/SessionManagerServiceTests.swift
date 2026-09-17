//
//  SessionManagerServiceTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerServiceTests {
    @Test func overtime_whenPastBudget() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 60)

        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()

        #expect(manager.phase == .overtime)
        #expect(manager.remainingSeconds < 0)
    }

    @Test func recoverOnLaunch_restoresOpenSession() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(start)
        let manager = SessionManager(modelContext: context, clock: clock)

        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        clock.advance(by: 45)

        let manager2 = SessionManager(modelContext: context, clock: clock)
        try manager2.recoverOnLaunch()

        #expect(manager2.phase == .running)
        #expect(manager2.activeSession?.ticket?.id == ticket.id)
        #expect(manager2.elapsedSeconds == 45)
    }

    @Test func endService_throwsWhileRunning() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)

        #expect(throws: SessionError.cannotEndServiceWhileRunning) {
            try manager.endService()
        }
    }

    @Test func endService_throwsWithUnresolvedPaused() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        try manager.board(ticket: a)
        try manager.pause()

        #expect(throws: SessionError.unresolvedPausedTickets) {
            try manager.endService()
        }
        #expect(manager.isInService == true)
        #expect(manager.pausedTicketCount == 1)
        #expect(a.isOpen)
    }

    @Test func endService_succeeds_afterResolvingPaused() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        try manager.board(ticket: a)
        try manager.pause()

        let paused = try #require(manager.pausedSessions.first)
        try manager.abandon(session: paused)
        try manager.endService()

        #expect(manager.isInService == false)
        #expect(manager.pausedTicketCount == 0)
        #expect(a.closureKind == .abandoned)
    }

    @Test func startService_throwsWhenPreviousDayStillOpen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(day1)
        let manager = SessionManager(
            modelContext: context,
            clock: clock,
            calendar: calendar,
            settings: AppSettings.makeForTesting()
        )
        try manager.startService()
        #expect(manager.isInService)

        clock.advance(by: day2.timeIntervalSince(day1))
        manager.reconcile()
        #expect(manager.needsServiceDayEndPrompt)

        #expect(throws: SessionError.serviceDayNeedsEnd) {
            try manager.startService()
        }
    }

    @Test func recoverOnLaunch_closesDuplicateOpenServiceDays() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        let older = ServiceDay(
            startedAt: clock.now.addingTimeInterval(-3600),
            calendarDayKey: "2099-01-01"
        )
        let newer = ServiceDay(
            startedAt: clock.now,
            calendarDayKey: ServiceDay.dayKey(for: clock.now, calendar: .current)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        try manager.recoverOnLaunch()
        #expect(older.endedAt != nil)
        #expect(newer.endedAt == nil)
        #expect(manager.activeServiceDay?.id == newer.id)
    }

    @Test func extend_increasesBudget_andLeavesOvertime() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 60)

        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .overtime)

        try manager.extend(by: 120)
        manager.reconcile()

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.budgetSecondsAtStart == 180)
        #expect(manager.remainingSeconds > 0)
    }

    @Test func extend_recordsReason() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        try manager.extend(by: 300, reason: "割り込みが入った")

        let session = try #require(manager.activeSession)
        #expect(session.extensions.count == 1)
        #expect(session.extensions.first?.addedSeconds == 300)
        #expect(session.extensions.first?.reason == "割り込みが入った")
    }

    @Test func arrive_recordsOvertimeResolution() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 60)
        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()
        try manager.arrive(resolution: .alreadyDone)

        #expect(ticket.sessions.first?.overtimeResolution == .alreadyDone)
        #expect(ticket.closureKind == .arrived)
    }

    @Test func partialDisembark_closesTicketWithPartialKind() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)

        try manager.board(ticket: ticket)
        try manager.partialDisembark()

        #expect(manager.phase == .idle)
        #expect(ticket.closureKind == .partialDisembark)
        #expect(ticket.closedAt != nil)
        #expect(ticket.sessions.first?.outcome == .partialDisembark)
    }

    @Test func abandon_closesTicket() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)

        try manager.board(ticket: ticket)
        try manager.abandon()

        #expect(manager.phase == .idle)
        #expect(ticket.closureKind == .abandoned)
        #expect(ticket.closedAt != nil)
    }

    @Test func pause_succeeds_afterAbandoningPaused() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        let b = try SessionManagerFixtures.makeTicket(context, title: "B")
        let c = try SessionManagerFixtures.makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)

        let pausedA = manager.pausedSessions.first { $0.ticket?.id == a.id }
        #expect(pausedA != nil)
        try manager.abandon(session: pausedA!)

        #expect(manager.pausedTicketCount == 1)
        try manager.board(ticket: c)
        try manager.pause()
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 2)
    }

    @Test func resume_stillAllowedWhenPausedAtLimit() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        let b = try SessionManagerFixtures.makeTicket(context, title: "B")
        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)
        try manager.board(ticket: a)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == a.id)
    }

    @Test func workSessions_onDayKey_includeOpenRides() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "A")
        try manager.board(ticket: ticket)
        let key = try #require(manager.activeServiceDay?.calendarDayKey)
        let sessions = manager.workSessions(onDayKey: key)
        #expect(sessions.count == 1)
        #expect(sessions.first?.ticket?.id == ticket.id)
        clock.advance(by: 60)
        try manager.arrive()
        #expect(manager.workSessions(onDayKey: key).count == 1)
    }
}
