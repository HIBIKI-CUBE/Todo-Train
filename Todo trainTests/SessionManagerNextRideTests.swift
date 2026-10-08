//
//  SessionManagerNextRideTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionManagerNextRideTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func reserveNextRide_whileRiding_doesNotBoard() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今")
        let next = try SessionManagerFixtures.makeTicket(context, title: "次")
        try manager.board(ticket: riding)
        let rideID = try #require(manager.activeSession?.id)

        try manager.reserveNextRide(ticket: next, via: .riding)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.id == rideID)
        #expect(manager.activeSession?.ticket?.id == riding.id)
        #expect(next.reservedAt == start)
        #expect(next.reservedFromRideId == rideID)
        #expect(next.reservedVia == .riding)
        #expect(manager.reservedNextTicket()?.id == next.id)
        #expect(riding.reservedAt == nil)
    }

    @Test func reserveNextRide_replacesThePreviousReservation() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今")
        let first = try SessionManagerFixtures.makeTicket(context, title: "先")
        let second = try SessionManagerFixtures.makeTicket(context, title: "後")
        try manager.board(ticket: riding)
        try manager.reserveNextRide(ticket: first, via: .riding)
        clock.advance(by: 30)

        try manager.reserveNextRide(ticket: second, via: .riding)

        #expect(first.reservedAt == nil)
        #expect(first.reservedFromRideId == nil)
        #expect(first.reservedVia == nil)
        #expect(second.reservedAt == start.addingTimeInterval(30))
        #expect(manager.reservedNextTicket()?.id == second.id)
        #expect(manager.phase == .running)
    }

    @Test func reserveNextRide_refusesTheCurrentTicketAndAClosedTicket() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今")
        let closed = try SessionManagerFixtures.makeTicket(context, title: "閉")
        closed.closedAt = .now
        try context.save()
        try manager.board(ticket: riding)

        #expect(throws: SessionError.cannotReserveCurrentRide) {
            try manager.reserveNextRide(ticket: riding, via: .riding)
        }
        #expect(throws: SessionError.ticketAlreadyClosed) {
            try manager.reserveNextRide(ticket: closed, via: .riding)
        }
        #expect(manager.reservedNextTicket() == nil)
    }

    @Test func reserveNextRide_refusesWithoutARide() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)

        #expect(throws: SessionError.noActiveSession) {
            try manager.reserveNextRide(ticket: ticket, via: .riding)
        }
        #expect(throws: SessionError.noActiveSession) {
            try manager.clearNextRideReservation()
        }
    }

    @Test func clearNextRideReservation_leavesTheRideRunning() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今")
        let next = try SessionManagerFixtures.makeTicket(context, title: "次")
        try manager.board(ticket: riding)
        try manager.reserveNextRide(ticket: next, via: .riding)

        try manager.clearNextRideReservation()

        #expect(next.reservedAt == nil)
        #expect(manager.reservedNextTicket() == nil)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == riding.id)
    }

    @Test func boardingTheReservedTicket_clearsOnlyThatReservation() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今")
        let reserved = try SessionManagerFixtures.makeTicket(context, title: "予約")
        let other = try SessionManagerFixtures.makeTicket(context, title: "別")
        try manager.board(ticket: riding)
        try manager.reserveNextRide(ticket: reserved, via: .riding)
        try manager.arrive()

        try manager.board(ticket: other)
        #expect(reserved.isReservedAsNextRide)
        #expect(manager.phase == .running)

        try manager.arrive()
        try manager.board(ticket: reserved)
        #expect(reserved.reservedAt == nil)
        #expect(reserved.reservedFromRideId == nil)
        #expect(reserved.reservedVia == nil)
        #expect(manager.reservedNextTicket() == nil)
    }

    @Test func resumingTheReservedTicket_clearsTheReservation() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let later = try SessionManagerFixtures.makeTicket(context, title: "あと")
        let reserved = try SessionManagerFixtures.makeTicket(context, title: "停車")
        try manager.board(ticket: reserved)
        try manager.pause()
        try manager.board(ticket: later)
        try manager.reserveNextRide(ticket: reserved, via: .riding)
        try manager.arrive()

        try manager.board(ticket: reserved)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == reserved.id)
        #expect(reserved.reservedAt == nil)
    }

    @Test func passengerAboard_refusesReserveAndClear() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context)
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今")
        let next = try SessionManagerFixtures.makeTicket(context, title: "次")
        try manager.board(ticket: riding)
        manager.boardPassenger()

        #expect(throws: SessionError.passengerAboard) {
            try manager.reserveNextRide(ticket: next, via: .riding)
        }
        next.reservedAt = start
        next.reservedVia = .riding
        #expect(throws: SessionError.passengerAboard) {
            try manager.clearNextRideReservation()
        }
        #expect(next.reservedAt == start)
    }

    private func insertBlock(_ context: ModelContext) -> TimetableBlock {
        let block = TimetableBlock(
            title: "週次",
            startsAt: start,
            endsAt: start.addingTimeInterval(3600),
            source: .manual
        )
        context.insert(block)
        try? context.save()
        return block
    }
}
