//
//  SessionManagerDeletionTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerDeletionTests {
    @Test func deleteTicket_removesUnusedTicket() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "誤作成")
        let id = ticket.id

        try manager.deleteTicket(ticket)

        let remaining = try context.fetch(FetchDescriptor<Ticket>())
        #expect(!remaining.contains { $0.id == id })
    }

    @Test func deleteTicket_whileRunning_clearsActiveSession() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)

        try manager.deleteTicket(ticket)

        #expect(manager.phase == .idle)
        #expect(manager.activeSession == nil)
        #expect(scheduler.cancelledSessionIDs.contains(sessionID))
        let tickets = try context.fetch(FetchDescriptor<Ticket>())
        #expect(tickets.isEmpty)
        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(sessions.isEmpty)
    }

    @Test func deleteEndedSession_removesRow_andOrphanTicket() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        try manager.arrive()
        let session = try #require(ticket.sessions.first)
        #expect(session.endedAt != nil)

        try manager.deleteEndedSession(session)

        #expect(try context.fetch(FetchDescriptor<WorkSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)
    }

    @Test func deleteEndedSession_keepsTicket_whenOtherSessionsRemain() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()

        let ticket = try SessionManagerFixtures.makeTicket(context, title: "二区間")
        let first = WorkSession(
            startedAt: clock.now,
            estimatedSecondsAtStart: 600,
            ticket: ticket
        )
        first.endedAt = clock.now.addingTimeInterval(100)
        first.outcome = .arrived
        first.accumulatedActiveSeconds = 100
        first.segmentStartedAt = nil
        context.insert(first)

        let second = WorkSession(
            startedAt: clock.now.addingTimeInterval(200),
            estimatedSecondsAtStart: 600,
            ticket: ticket
        )
        second.endedAt = clock.now.addingTimeInterval(300)
        second.outcome = .arrived
        second.accumulatedActiveSeconds = 100
        second.segmentStartedAt = nil
        context.insert(second)
        ticket.closedAt = clock.now.addingTimeInterval(300)
        ticket.closureKind = .arrived
        try context.save()

        try manager.deleteEndedSession(first)

        let tickets = try context.fetch(FetchDescriptor<Ticket>())
        #expect(tickets.count == 1)
        #expect(tickets.first?.id == ticket.id)
        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == second.id)
    }

    @Test func restoreDeletedTicket_afterDelete_returnsTicket() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "誤作成")
        let record = DeletionUndo.captureTicket(ticket)
        let id = ticket.id

        try manager.deleteTicket(ticket)
        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)

        try manager.restoreDeletedTicket(record)

        let restored = try context.fetch(FetchDescriptor<Ticket>())
        #expect(restored.contains { $0.id == id })
        #expect(restored.first?.title == "誤作成")
    }

    @Test func restoreDeletedTicket_whileRunning_restoresPhase() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        let id = ticket.id
        let record = DeletionUndo.captureTicket(ticket)

        try manager.deleteTicket(ticket)
        #expect(manager.phase == .idle)

        try manager.restoreDeletedTicket(record)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == id)
    }

    @Test func restoreDeletedSession_lastRow_restoresTicket() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "到着済")
        try manager.board(ticket: ticket)
        try manager.arrive()
        let session = try #require(ticket.sessions.first)
        let record = DeletionUndo.captureTicket(ticket)

        try manager.deleteEndedSession(session)
        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)

        try manager.restoreDeletedTicket(record)
        #expect(try context.fetch(FetchDescriptor<Ticket>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<WorkSession>()).count == 1)
    }

    @Test func deleteEndedSession_rejectsOpenSession() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        let session = try #require(manager.activeSession)

        #expect(throws: SessionError.cannotDeleteOpenSession) {
            try manager.deleteEndedSession(session)
        }
    }
}
