//
//  BoardingEligibilityTests.swift
//  Todo trainTests
//

import Foundation
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
}
