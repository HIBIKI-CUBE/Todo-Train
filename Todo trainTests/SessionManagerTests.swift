//
//  SessionManagerTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionManagerTests {
    private func makeHarness(
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> (SessionManager, ModelContext, FixedSessionClock) {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(now)
        let manager = SessionManager(modelContext: context, clock: clock)
        return (manager, context, clock)
    }

    private func makeTicket(
        _ context: ModelContext,
        title: String = "A",
        seconds: Int = 1800
    ) throws -> Ticket {
        let ticket = Ticket(title: title, estimatedSeconds: seconds)
        context.insert(ticket)
        try context.save()
        return ticket
    }

    @Test func startService_thenBoard_setsRunning() throws {
        let (manager, context, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == ticket.id)
        #expect(manager.elapsedSeconds >= 0)
    }

    @Test func cannotBoard_withoutService() throws {
        let (manager, context, _) = try makeHarness()
        let ticket = try makeTicket(context)

        #expect(throws: SessionError.noActiveService) {
            try manager.board(ticket: ticket)
        }
    }

    @Test func cannotBoard_secondTicket_whileRunning() throws {
        let (manager, context, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")

        try manager.board(ticket: a)

        #expect(throws: SessionError.alreadyBoarding) {
            try manager.board(ticket: b)
        }
    }

    @Test func pause_accumulatesElapsed_andStopsGrowth() throws {
        let (manager, context, clock) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 120)
        manager.reconcile()
        let elapsedBeforePause = manager.elapsedSeconds

        try manager.pause()
        #expect(manager.phase == .paused)
        #expect(elapsedBeforePause == 120)

        clock.advance(by: 300)
        manager.reconcile()
        #expect(manager.elapsedSeconds == 120)
    }

    @Test func resume_continuesFromPaused() throws {
        let (manager, context, clock) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 60)
        try manager.pause()
        clock.advance(by: 100)
        try manager.resume()
        clock.advance(by: 30)
        manager.reconcile()

        #expect(manager.phase == .running)
        #expect(manager.elapsedSeconds == 90)
    }

    @Test func pause_blocked_whenTwoPaused() throws {
        let (manager, context, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)

        try manager.board(ticket: c)
        #expect(manager.phase == .running)

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.pause()
        }
    }

    @Test func arrive_closesSessionAndTicket() throws {
        let (manager, context, clock) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)
        clock.advance(by: 10)
        try manager.arrive()

        #expect(manager.phase == .idle)
        #expect(manager.activeSession == nil)
        #expect(ticket.closedAt != nil)
        #expect(ticket.closureKind == .arrived)
        #expect(ticket.sessions.first?.outcome == .arrived)
        #expect(ticket.sessions.first?.endedAt != nil)
    }

    @Test func overtime_whenPastBudget() throws {
        let (manager, context, clock) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 60)

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
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        clock.advance(by: 45)

        let manager2 = SessionManager(modelContext: context, clock: clock)
        try manager2.recoverOnLaunch()

        #expect(manager2.phase == .running)
        #expect(manager2.activeSession?.ticket?.id == ticket.id)
        #expect(manager2.elapsedSeconds == 45)
    }

    @Test func endService_throwsWhileRunning() throws {
        let (manager, context, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)

        #expect(throws: SessionError.cannotEndServiceWhileRunning) {
            try manager.endService()
        }
    }

    @Test func extend_increasesBudget_andLeavesOvertime() throws {
        let (manager, context, clock) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 60)

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

    @Test func partialDisembark_closesTicketWithPartialKind() throws {
        let (manager, context, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)
        try manager.partialDisembark()

        #expect(manager.phase == .idle)
        #expect(ticket.closureKind == .partialDisembark)
        #expect(ticket.closedAt != nil)
        #expect(ticket.sessions.first?.outcome == .partialDisembark)
    }

    @Test func abandon_closesTicket() throws {
        let (manager, context, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)
        try manager.abandon()

        #expect(manager.phase == .idle)
        #expect(ticket.closureKind == .abandoned)
        #expect(ticket.closedAt != nil)
    }

    @Test func pause_succeeds_afterAbandoningPaused() throws {
        let (manager, context, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)

        try manager.board(ticket: c)
        let pausedA = manager.pausedSessions.first { $0.ticket?.id == a.id }
        #expect(pausedA != nil)
        try manager.abandon(session: pausedA!)

        #expect(manager.pausedTicketCount == 1)
        try manager.pause()
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 2)
    }
}
