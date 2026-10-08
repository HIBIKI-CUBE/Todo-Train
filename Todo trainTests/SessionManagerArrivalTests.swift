//
//  SessionManagerArrivalTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionManagerArrivalTests {
    @Test func arrive_momentNamesTheClosedRide() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let rideID = try #require(manager.activeSession?.id)
        try manager.arrive()

        #expect(manager.punctualityMoment?.arrivedSessionID == rideID)
        let ride = try #require(manager.fetchWorkSession(id: rideID))
        #expect(ride.outcome == .arrived)
        #expect(ride.endedAt != nil)
        #expect(ride.arrivalAction == nil)
        #expect(ride.arrivalStampedAt == nil)
    }

    @Test func recordArrivalStamp_doesNotBoardOrExtend() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        let next = try SessionManagerFixtures.makeTicket(context, title: "次")
        try manager.board(ticket: ticket)
        let rideID = try #require(manager.activeSession?.id)
        let budget = try #require(manager.activeSession?.budgetSecondsAtStart)
        try manager.reserveNextRide(ticket: next, via: .riding)
        try manager.arrive()
        clock.advance(by: 5)

        try manager.recordArrivalStamp(sessionID: rideID, action: .nextRide)

        let ride = try #require(manager.fetchWorkSession(id: rideID))
        #expect(ride.outcome == .arrived)
        #expect(ride.endedAt != nil)
        #expect(ride.arrivalAction == .nextRide)
        #expect(ride.arrivalStampedAt == clock.now)
        #expect(ride.budgetSecondsAtStart == budget)
        #expect(manager.phase == .idle)
        #expect(manager.activeSession == nil)
        #expect(manager.punctualityMoment?.arrivedSessionID == rideID)
        #expect(next.sessions.isEmpty)
    }

    @Test func dismissWithoutStamp_keepsTheArrivalRecord() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        let rideID = try #require(manager.activeSession?.id)
        try manager.arrive()

        manager.consumePunctualityMoment()

        let ride = try #require(manager.fetchWorkSession(id: rideID))
        #expect(ride.outcome == .arrived)
        #expect(ride.endedAt != nil)
        #expect(ride.arrivalAction == nil)
        #expect(ride.arrivalStampedAt == nil)
        #expect(manager.phase == .idle)
    }

    @Test func issueArrivalInstant_doesNotBoard() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今")
        try manager.board(ticket: riding)
        try manager.arrive()
        let before = try context.fetch(FetchDescriptor<WorkSession>()).count

        let issued = try manager.issueArrivalInstant(title: "続き", minutes: 25)

        #expect(issued.title == "続き")
        #expect(issued.isOpen)
        #expect(issued.sessions.isEmpty)
        #expect(manager.phase == .idle)
        #expect(manager.activeSession == nil)
        #expect(try context.fetch(FetchDescriptor<WorkSession>()).count == before)
        #expect(manager.settings.lastIssuedEstimateMinutes == 25)
    }

    @Test func issueArrivalInstant_emptyTitle_insertsNothing() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let before = try context.fetch(FetchDescriptor<Ticket>()).count

        #expect(throws: SessionError.emptyTicketTitle) {
            try manager.issueArrivalInstant(title: "   ", minutes: 10)
        }
        #expect(try context.fetch(FetchDescriptor<Ticket>()).count == before)
        #expect(manager.phase == .idle)
    }

    @Test func boardingElsewhere_consumesTheArrivalCelebration() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今", seconds: 600)
        let other = try SessionManagerFixtures.makeTicket(context, title: "別")
        try manager.board(ticket: riding)
        clock.advance(by: 560)
        try manager.arrive()
        try manager.endService()
        #expect(manager.punctualityQueue.count == 2)

        try manager.startService()
        try manager.board(ticket: other)

        #expect(manager.phase == .running)
        #expect(manager.punctualityQueue.allSatisfy { moment in
            if case .arrival = moment.kind { return false }
            return true
        })
        #expect(manager.punctualityMoment?.kind == .onTimeService)
    }
}
