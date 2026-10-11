//
//  BoardingEligibilityTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct BoardingEligibilityTests {
    @Test func evaluate_priorityMatchesHubOrder() {
        #expect(
            BoardingEligibility.evaluate(
                isInService: false,
                needsServiceDayEnd: true,
                hasRunningRide: true,
                passengerLocksDriving: true,
                canBoardNewRide: false
            ) == .blocked(.passengerAboard)
        )
        #expect(
            BoardingEligibility.evaluate(
                isInService: false,
                needsServiceDayEnd: true,
                hasRunningRide: true,
                passengerLocksDriving: false,
                canBoardNewRide: false
            ) == .blocked(.serviceDayNeedsEnd)
        )
        #expect(
            BoardingEligibility.evaluate(
                isInService: false,
                needsServiceDayEnd: false,
                hasRunningRide: false,
                passengerLocksDriving: false,
                canBoardNewRide: true
            ) == .blocked(.noActiveService)
        )
        #expect(
            BoardingEligibility.evaluate(
                isInService: true,
                needsServiceDayEnd: false,
                hasRunningRide: true,
                passengerLocksDriving: false,
                canBoardNewRide: true
            ) == .blocked(.alreadyBoarding)
        )
        #expect(
            BoardingEligibility.evaluate(
                isInService: true,
                needsServiceDayEnd: false,
                hasRunningRide: false,
                passengerLocksDriving: false,
                canBoardNewRide: false
            ) == .blocked(.pauseLimitReached)
        )
        #expect(
            BoardingEligibility.evaluate(
                isInService: true,
                needsServiceDayEnd: false,
                hasRunningRide: false,
                passengerLocksDriving: false,
                canBoardNewRide: true
            ) == .allowed
        )
    }

    @Test func allowsInteraction_softPauseLimitOnly() {
        #expect(
            BoardingEligibility.blocked(.pauseLimitReached).allowsInteraction
        )
        #expect(
            !BoardingEligibility.blocked(.alreadyBoarding).allowsInteraction
        )
        #expect(
            !BoardingEligibility.blocked(.noActiveService).allowsInteraction
        )
        #expect(
            !BoardingEligibility.blocked(.serviceDayNeedsEnd).allowsInteraction
        )
        #expect(
            !BoardingEligibility.blocked(.passengerAboard).allowsInteraction
        )
        #expect(BoardingEligibility.allowed.allowsInteraction)
    }

    @Test func disabledReason_usesSessionErrorCopy() {
        #expect(
            BoardingEligibility.blocked(.serviceDayNeedsEnd).disabledReason
                == SessionError.serviceDayNeedsEnd.errorDescription
        )
        #expect(
            BoardingEligibility.blocked(.pauseLimitReached).disabledReason
                == SessionError.pauseLimitReached.errorDescription
        )
        #expect(
            BoardingEligibility.blocked(.noActiveService).disabledReason
                == SessionError.noActiveService.errorDescription
        )
    }

    @Test func assertCanBoardOrResume_ignoresPauseLimit() throws {
        try BoardingEligibility.blocked(.pauseLimitReached).assertCanBoardOrResume()
        #expect(throws: SessionError.alreadyBoarding) {
            try BoardingEligibility.blocked(.alreadyBoarding).assertCanBoardOrResume()
        }
    }

    @Test func assertCanStartNewRide_includesPauseLimit() {
        #expect(throws: SessionError.pauseLimitReached) {
            try BoardingEligibility.blocked(.pauseLimitReached).assertCanStartNewRide()
        }
    }

    @Test func assertBeforeAdoptingRunningSession_defersRideAndPauseLimit() throws {
        try BoardingEligibility.blocked(.alreadyBoarding).assertBeforeAdoptingRunningSession()
        try BoardingEligibility.blocked(.pauseLimitReached).assertBeforeAdoptingRunningSession()
        try BoardingEligibility.allowed.assertBeforeAdoptingRunningSession()
        #expect(throws: SessionError.passengerAboard) {
            try BoardingEligibility.blocked(.passengerAboard).assertBeforeAdoptingRunningSession()
        }
        #expect(throws: SessionError.serviceDayNeedsEnd) {
            try BoardingEligibility.blocked(.serviceDayNeedsEnd).assertBeforeAdoptingRunningSession()
        }
        #expect(throws: SessionError.noActiveService) {
            try BoardingEligibility.blocked(.noActiveService).assertBeforeAdoptingRunningSession()
        }
    }
}

@MainActor
struct BoardingEligibilitySessionTests {
    @Test func boardingEligibility_matchesRunningSessionNotStalePhase() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        #expect(manager.boardingEligibility == .blocked(.alreadyBoarding))
        #expect(!manager.boardingEligibility.allowsInteraction)

        try manager.pause()
        #expect(manager.boardingEligibility == .allowed)
        #expect(manager.boardingEligibility.allowsInteraction)
    }

    @Test func board_resumeStillWorksAtPauseLimit() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A", seconds: 600)
        let b = try SessionManagerFixtures.makeTicket(context, title: "B", seconds: 600)
        let c = try SessionManagerFixtures.makeTicket(context, title: "C", seconds: 600)
        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        #expect(manager.boardingEligibility == .blocked(.pauseLimitReached))
        #expect(manager.boardingEligibility.allowsInteraction)

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.board(ticket: c)
        }

        try manager.board(ticket: a)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == a.id)
    }

    @Test func board_passengerOutranksServiceDayEnd() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: clock.now))
        context.insert(
            ServiceDay(
                startedAt: yesterday,
                calendarDayKey: ServiceDay.dayKey(for: yesterday, calendar: .current)
            )
        )
        try insertOpenPassenger(context, at: clock.now)
        let ticket = try SessionManagerFixtures.makeTicket(context)

        #expect(throws: SessionError.passengerAboard) {
            try manager.board(ticket: ticket)
        }
        #expect(manager.needsServiceDayEndPrompt)
        #expect(manager.activeSession == nil)
    }

    @Test func board_serviceDayEndStillBlocksWithoutPassenger() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: clock.now))
        context.insert(
            ServiceDay(
                startedAt: yesterday,
                calendarDayKey: ServiceDay.dayKey(for: yesterday, calendar: .current)
            )
        )
        try context.save()
        let ticket = try SessionManagerFixtures.makeTicket(context)

        #expect(throws: SessionError.serviceDayNeedsEnd) {
            try manager.board(ticket: ticket)
        }
        #expect(manager.activeSession == nil)
    }

    @Test func board_passengerOutranksRunningSessionAdoption() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let running = try SessionManagerFixtures.makeTicket(context, title: "走行", seconds: 600)
        try manager.board(ticket: running)
        let runningID = manager.activeSession?.id
        manager.phase = .idle
        manager.activeSession = nil
        try insertOpenPassenger(context, at: clock.now)
        let other = try SessionManagerFixtures.makeTicket(context, title: "別", seconds: 600)

        #expect(throws: SessionError.passengerAboard) {
            try manager.board(ticket: other)
        }
        #expect(manager.activeSession == nil)
        #expect(manager.phase == .idle)
        #expect(manager.fetchRunningSession()?.id == runningID)
    }

    @Test func board_adoptsRunningSessionWhenPhaseIsStale() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let running = try SessionManagerFixtures.makeTicket(context, title: "走行", seconds: 600)
        try manager.board(ticket: running)
        manager.phase = .idle
        manager.activeSession = nil
        let other = try SessionManagerFixtures.makeTicket(context, title: "別", seconds: 600)

        #expect(throws: SessionError.alreadyBoarding) {
            try manager.board(ticket: other)
        }
        #expect(manager.activeSession?.ticket?.id == running.id)
        #expect(manager.phase == .running)
    }

    @Test func board_passengerOutranksClosedTicket() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        try insertOpenPassenger(context, at: clock.now)
        let ticket = try SessionManagerFixtures.makeTicket(context)
        ticket.closedAt = clock.now

        #expect(throws: SessionError.passengerAboard) {
            try manager.board(ticket: ticket)
        }
    }
}

private func insertOpenPassenger(_ context: ModelContext, at now: Date) throws {
    context.insert(
        PassengerRide(
            intervalId: "passenger",
            title: "案内",
            intervalStart: now,
            intervalEnd: now.addingTimeInterval(3600),
            boardedAt: now,
            source: .manualInterval
        )
    )
    try context.save()
}
