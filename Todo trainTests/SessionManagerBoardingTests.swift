//
//  SessionManagerBoardingTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerBoardingTests {
    @Test func startService_thenBoard_setsRunning() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)

        try manager.board(ticket: ticket)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == ticket.id)
        #expect(manager.elapsedSeconds >= 0)
    }

    @Test func cannotBoard_withoutService() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        let ticket = try SessionManagerFixtures.makeTicket(context)

        #expect(throws: SessionError.noActiveService) {
            try manager.board(ticket: ticket)
        }
    }

    @Test func cannotBoard_secondTicket_whileRunning() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        let b = try SessionManagerFixtures.makeTicket(context, title: "B")

        try manager.board(ticket: a)

        #expect(throws: SessionError.alreadyBoarding) {
            try manager.board(ticket: b)
        }
    }

    @Test func pause_accumulatesElapsed_andStopsGrowth() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

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
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

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

    @Test func pause_recordsInterval_untilResume() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 60)
        try manager.pause()

        let session = try #require(manager.activeSession)
        #expect(session.pauses.count == 1)
        #expect(session.pauses.first?.startedAt == clock.now)
        #expect(session.pauses.first?.endedAt == nil)

        clock.advance(by: 180)
        try manager.resume()

        let pause = try #require(session.pauses.first)
        #expect(pause.endedAt == clock.now)
        #expect(pause.endedAt?.timeIntervalSince(pause.startedAt) == 180)
        #expect(session.pauses.filter { $0.endedAt == nil }.isEmpty)
    }

    @Test func pause_secondInterval_appendsAnotherRecord() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        try manager.pause()
        clock.advance(by: 30)
        try manager.resume()
        clock.advance(by: 20)
        try manager.pause()
        clock.advance(by: 40)
        try manager.resume()

        let session = try #require(manager.activeSession)
        let pauses = session.pauses.sorted { $0.startedAt < $1.startedAt }
        #expect(pauses.count == 2)
        #expect(pauses[0].endedAt?.timeIntervalSince(pauses[0].startedAt) == 30)
        #expect(pauses[1].endedAt?.timeIntervalSince(pauses[1].startedAt) == 40)
    }

    @Test func switchBoard_recordsPauseOnParkedRide() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A", seconds: 600)
        let b = try SessionManagerFixtures.makeTicket(context, title: "B", seconds: 300)
        try manager.board(ticket: a)
        clock.advance(by: 90)
        try manager.switchBoard(ticket: b)

        let parked = try #require(manager.pausedSessions.first)
        #expect(parked.pauses.count == 1)
        #expect(parked.pauses.first?.endedAt == nil)
        #expect(parked.pauses.first?.startedAt == clock.now)
    }

    @Test func arrive_whilePaused_closesOpenPause() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        clock.advance(by: 30)
        try manager.pause()
        clock.advance(by: 50)
        try manager.arrive()

        let session = try #require(ticket.sessions.first)
        let pause = try #require(session.pauses.first)
        #expect(pause.endedAt == session.endedAt)
        #expect(pause.endedAt?.timeIntervalSince(pause.startedAt) == 50)
    }

    @Test func pause_alwaysAllowed_boardBlockedWhenTwoPaused() throws {
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

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.board(ticket: c)
        }
        try manager.board(ticket: a)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == a.id)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)
        #expect(manager.phase == .paused)
    }

    @Test func board_allowed_whenLimitIsThree() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(pauseLimit: 3)
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        let b = try SessionManagerFixtures.makeTicket(context, title: "B")
        let c = try SessionManagerFixtures.makeTicket(context, title: "C")
        let d = try SessionManagerFixtures.makeTicket(context, title: "D")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        try manager.board(ticket: c)
        try manager.pause()
        #expect(manager.pausedTicketCount == 3)

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.board(ticket: d)
        }
    }

    @Test func switchBoard_pausesCurrent_andRunsNew_withoutPausedPhase() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A", seconds: 600)
        let b = try SessionManagerFixtures.makeTicket(context, title: "B", seconds: 300)

        try manager.board(ticket: a)
        clock.advance(by: 90)
        manager.reconcile()

        try manager.switchBoard(ticket: b)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == b.id)
        #expect(manager.pausedTicketCount == 1)
        #expect(manager.pausedSessions.first?.ticket?.id == a.id)
        #expect(manager.pausedSessions.first?.elapsedSeconds(at: clock.now) == 90)

        clock.advance(by: 40)
        manager.reconcile()
        #expect(manager.elapsedSeconds == 40)
        #expect(manager.pausedSessions.first?.elapsedSeconds(at: clock.now) == 90)
    }

    @Test func switchBoard_blocked_whenPauseLimitReached_keepsCurrentRunning() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        let b = try SessionManagerFixtures.makeTicket(context, title: "B")
        let c = try SessionManagerFixtures.makeTicket(context, title: "C")
        let d = try SessionManagerFixtures.makeTicket(context, title: "D")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.switchBoard(ticket: c)
        #expect(manager.pausedTicketCount == 2)
        #expect(manager.activeSession?.ticket?.id == c.id)

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.switchBoard(ticket: d)
        }
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == c.id)
        #expect(manager.pausedTicketCount == 2)
    }

    @Test func switchBoard_allowed_whenOneAlreadyPaused() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        let b = try SessionManagerFixtures.makeTicket(context, title: "B")
        let c = try SessionManagerFixtures.makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.switchBoard(ticket: c)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == c.id)
        #expect(manager.pausedTicketCount == 2)
    }

    @Test func switchBoard_toPausedTicket_allowedAtLimit() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A")
        let b = try SessionManagerFixtures.makeTicket(context, title: "B")
        let c = try SessionManagerFixtures.makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.switchBoard(ticket: c)
        #expect(manager.pausedTicketCount == 2)

        try manager.switchBoard(ticket: a)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == a.id)
        #expect(manager.pausedTicketCount == 2)
        #expect(manager.pausedSessions.contains { $0.ticket?.id == c.id })
    }

    @Test func switchBoard_sameTicket_isNoOp() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)

        try manager.board(ticket: ticket)
        try manager.switchBoard(ticket: ticket)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == ticket.id)
        #expect(manager.pausedTicketCount == 0)
    }

    @Test func arrive_closesSessionAndTicket() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)

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

    @Test func rideMutations_bumpCompanionSyncTick() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 60)
        #expect(manager.companionSyncTick == 1)

        try manager.board(ticket: ticket)
        #expect(manager.companionSyncTick == 2)

        try manager.pause()
        #expect(manager.companionSyncTick == 3)

        try manager.resume()
        #expect(manager.companionSyncTick == 4)

        try manager.extend(by: 60)
        #expect(manager.companionSyncTick == 5)

        clock.advance(by: 121)
        manager.reconcile()
        #expect(manager.phase == .overtime)
        #expect(manager.companionSyncTick == 6)
        manager.reconcile()
        #expect(manager.companionSyncTick == 6)

        try manager.arrive()
        #expect(manager.companionSyncTick == 7)
        #expect(manager.phase == .idle)
    }
}
