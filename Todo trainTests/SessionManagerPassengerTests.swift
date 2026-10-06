//
//  SessionManagerPassengerTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionManagerPassengerTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func insertBlock(
        _ context: ModelContext,
        title: String = "週次",
        source: TimetableSource = .manual,
        startOffset: TimeInterval = 0,
        duration: TimeInterval = 3600
    ) -> TimetableBlock {
        let block = TimetableBlock(
            title: title,
            startsAt: start.addingTimeInterval(startOffset),
            endsAt: start.addingTimeInterval(startOffset + duration),
            source: source
        )
        context.insert(block)
        try? context.save()
        return block
    }

    private func rides(_ context: ModelContext) -> [PassengerRide] {
        (try? context.fetch(FetchDescriptor<PassengerRide>())) ?? []
    }

    @Test func ignoreLeavesNoRideAndATSStillStopsTheTicket() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)

        guard case .offer = manager.passengerChrome else {
            Issue.record("expected an offer beside the running ticket")
            return
        }
        #expect(rides(context).isEmpty)
        #expect(manager.phase == .running)

        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .paused)
        #expect(manager.activeSession?.timetableHeld == true)
        #expect(rides(context).isEmpty)
    }

    @Test func boardingWhileRunningHoldsThenSeparatesTheRide() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let block = insertBlock(context)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        let sessionID = manager.activeSession?.id

        manager.boardPassenger()

        #expect(manager.phase == .paused)
        #expect(manager.activeSession?.id == sessionID)
        #expect(manager.activeSession?.timetableHeld == true)
        #expect(manager.activeSession?.isOpen == true)
        #expect(manager.pausedCountTowardLimit == 0)
        let ride = try #require(rides(context).first)
        #expect(ride.intervalId == block.id.uuidString)
        #expect(ride.boardedAt == start)
        #expect(ride.endedAt == nil)
        #expect(ride.source == .manualInterval)
        guard case .aboard = manager.passengerChrome else {
            Issue.record("expected the cabin")
            return
        }
        #expect(throws: SessionError.passengerAboard) {
            try manager.resume()
        }

        clock.advance(by: 3600)
        manager.reconcile()
        #expect(ride.endReason == .arrived)
        #expect(manager.phase == .paused)
        #expect(manager.activeSession?.isOpen == true)
        guard case .arrived = manager.passengerChrome else {
            Issue.record("expected the short ただいま")
            return
        }

        clock.advance(by: PassengerLane.arrivedGreeting)
        manager.reconcile()
        #expect(manager.passengerChrome == .none)
        #expect(manager.phase == .paused)
    }

    @Test func manualPauseDoesNotSpendAnotherSlot() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context)
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        try manager.pause()
        #expect(manager.pausedCountTowardLimit == 1)
        #expect(manager.activeSession?.timetableHeld == false)

        manager.boardPassenger()

        #expect(manager.pausedCountTowardLimit == 1)
        #expect(manager.activeSession?.timetableHeld == false)
        #expect(rides(context).count == 1)
    }

    @Test func emergencyIsDistinctAndCanBeOfferedAgain() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, duration: 3600)
        manager.reconcile()
        manager.boardPassenger()
        let ride = try #require(rides(context).first)

        manager.openEmergencyDoor()
        #expect(ride.endReason == .emergency)
        #expect(ride.endedAt != nil)
        guard case .doorOpened = manager.passengerChrome else {
            Issue.record("expected ドアを開けました")
            return
        }

        clock.advance(by: PassengerLane.doorOpenedGreeting)
        manager.reconcile()
        guard case .offer = manager.passengerChrome else {
            Issue.record("expected to offer the same interval again")
            return
        }
        #expect(manager.fetchOpenPassengerRide() == nil)

        manager.boardPassenger()
        #expect(rides(context).count == 2)
        #expect(rides(context).filter(\.isOpen).count == 1)
    }

    @Test func cancellationUnlocksWithoutAnOffer() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let block = insertBlock(context)
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        manager.boardPassenger()
        block.isCancelled = true
        try context.save()

        manager.reconcile()
        let ride = try #require(rides(context).first)
        #expect(ride.endReason == .cancelled)
        #expect(manager.passengerChrome.locksDriving == false)
        #expect(manager.phase == .paused)
        try manager.resume()
        #expect(manager.phase == .running)
    }

    @Test func calendarDeniedHidesAdoptedBlocksAndKeepsManual() throws {
        let board = InMemoryCalendarBoard()
        board.status = .denied
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            calendarBoard: board
        )
        _ = insertBlock(context, title: "会議", source: .calendar)
        manager.reconcile()
        #expect(manager.passengerChrome == .none)

        _ = insertBlock(context, title: "手", source: .manual)
        manager.reconcile()
        guard case .offer(let interval, _) = manager.passengerChrome else {
            Issue.record("manual interval should still offer")
            return
        }
        #expect(interval.title == "手")
        #expect(interval.source == .manualInterval)
    }

    @Test func aboardSuppressesAwayAndIdleCabin() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let day = try #require(manager.activeServiceDay)
        day.lastCabinActivityAt = start.addingTimeInterval(-21 * 60)
        manager.refreshIdleCabin(now: start)
        #expect(day.pendingCabin == .idle)

        _ = insertBlock(context)
        manager.boardPassenger()
        #expect(day.pendingCabin == nil)

        let ticket = try SessionManagerFixtures.makeTicket(context)
        // The open ride still locks driving, so a new ticket cannot board.
        #expect(throws: SessionError.passengerAboard) {
            try manager.board(ticket: ticket)
        }
        manager.openEmergencyDoor()
        clockAdvancePastDoor(manager)

        try manager.board(ticket: ticket)
        context.insert(
            PassengerRide(
                intervalId: "still",
                title: "残る",
                intervalStart: start,
                intervalEnd: start.addingTimeInterval(3600),
                boardedAt: start,
                source: .manualInterval
            )
        )
        try context.save()
        manager.beginAwayWatch()
        #expect(manager.activeSession?.awayDueAt == nil)
    }

    @Test func upcomingIntervalSchedulesOneNotificationUnlessTheTicketIsRunning() throws {
        let notifier = InMemoryCheckInNotifier()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            checkInNotifier: notifier
        )
        try manager.startService()
        let block = insertBlock(context, startOffset: 120)
        manager.reconcile()
        #expect(notifier.passenger.map(\.intervalID) == [block.id.uuidString])

        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        #expect(notifier.passenger.isEmpty)
        guard case .soon = manager.passengerChrome else {
            Issue.record("the soon band stays on the running ticket")
            return
        }
    }

    private func clockAdvancePastDoor(_ manager: SessionManager) {
        manager.reconcile(now: start.addingTimeInterval(PassengerLane.doorOpenedGreeting + 1))
    }
}
