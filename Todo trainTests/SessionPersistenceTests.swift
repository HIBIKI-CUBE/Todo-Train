//
//  SessionPersistenceTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionPersistenceTests {
    @Test func saveBestEffort_returnsTrueAfterMutation() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)

        #expect(manager.saveBestEffort())
        #expect(manager.activeSession?.ticket?.id == ticket.id)
    }

    @Test func restoreDeletedTicket_throwsAreNotSwallowedByAPI() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "戻す", seconds: 600)
        let record = DeletionUndo.captureTicket(ticket)
        try manager.deleteTicket(ticket)

        try manager.restoreDeletedTicket(record)
        let restored = try context.fetch(FetchDescriptor<Ticket>()).first { $0.id == record.id }
        #expect(restored?.title == "戻す")
    }

    @Test func adoptOccurrence_failedSave_dropsTheBlock() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        let occurrence = CalendarOccurrence(
            eventIdentifier: "evt",
            title: "週次",
            startsAt: Date(timeIntervalSince1970: 1_700_000_000),
            endsAt: Date(timeIntervalSince1970: 1_700_003_600),
            isAllDay: false,
            isDeclined: false
        )
        manager.saveErrorForTesting = ForcedSaveFailure()
        manager.adoptOccurrence(occurrence, scope: .occurrence)

        #expect(manager.fetchTimetableBlocks().isEmpty)
        #expect(manager.fetchSeriesRules().isEmpty)
        manager.saveErrorForTesting = nil
        try manager.save()
        #expect(manager.fetchTimetableBlocks().isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimetableBlock>()).isEmpty)
    }

    @Test func unadopt_failedSave_keepsTheBlockActive() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        let block = TimetableBlock(
            title: "週次",
            startsAt: start,
            endsAt: start.addingTimeInterval(3600),
            source: .manual
        )
        context.insert(block)
        try context.save()

        manager.saveErrorForTesting = ForcedSaveFailure()
        manager.unadopt(blockID: block.id, scope: .occurrence)

        #expect(block.isCancelled == false)
        manager.saveErrorForTesting = nil
        try manager.save()
        #expect(block.isCancelled == false)
        let stored = try context.fetch(FetchDescriptor<TimetableBlock>())
        #expect(stored.count == 1)
        #expect(stored.first?.isCancelled == false)
    }

    @Test func boardPassenger_failedSave_doesNotLockDriving() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let block = TimetableBlock(
            title: "週次",
            startsAt: start,
            endsAt: start.addingTimeInterval(3600),
            source: .manual
        )
        context.insert(block)
        try context.save()
        manager.reconcile()

        manager.saveErrorForTesting = ForcedSaveFailure()
        manager.boardPassenger()

        #expect(manager.passengerChrome.locksDriving == false)
        #expect(try context.fetch(FetchDescriptor<PassengerRide>()).isEmpty)
        manager.saveErrorForTesting = nil
        try manager.save()
        #expect(try context.fetch(FetchDescriptor<PassengerRide>()).isEmpty)
    }

    @Test func openEmergencyDoor_failedSave_keepsTheRideOpen() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let block = TimetableBlock(
            title: "週次",
            startsAt: start,
            endsAt: start.addingTimeInterval(3600),
            source: .manual
        )
        context.insert(block)
        try context.save()
        manager.reconcile()
        manager.boardPassenger()
        let ride = try #require(try context.fetch(FetchDescriptor<PassengerRide>()).first)

        manager.saveErrorForTesting = ForcedSaveFailure()
        manager.openEmergencyDoor()

        #expect(ride.endedAt == nil)
        #expect(ride.endReason == nil)
        guard case .aboard = manager.passengerChrome else {
            Issue.record("expected the cabin to stay aboard")
            return
        }
        manager.saveErrorForTesting = nil
        try manager.save()
        #expect(ride.endedAt == nil)
        #expect(ride.endReason == nil)
    }

    @Test func fireAwayInterrupt_failedSave_restoresTheWatch() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        let session = try #require(manager.activeSession)
        let due = manager.clock.now.addingTimeInterval(40)
        session.awayDueAt = due
        try manager.save()

        manager.saveErrorForTesting = ForcedSaveFailure()
        manager.fireAwayInterrupt(session, now: manager.clock.now, presentAlert: false)

        #expect(session.pendingCheckIn == nil)
        #expect(session.awayDueAt == due)
    }
}

private struct ForcedSaveFailure: Error {}
