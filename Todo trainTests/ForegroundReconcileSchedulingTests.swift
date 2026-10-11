//
//  ForegroundReconcileSchedulingTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct ForegroundReconcileSchedulingTests {
    @Test func needsTick_openRideOrPassengerChrome() {
        #expect(
            ForegroundReconcileScheduling.needsTick(hasOpenRide: true, passengerChrome: .none)
        )
        #expect(
            !ForegroundReconcileScheduling.needsTick(hasOpenRide: false, passengerChrome: .none)
        )

        let interval = PassengerInterval(
            id: "i",
            title: "案内",
            startsAt: Date(timeIntervalSince1970: 0),
            endsAt: Date(timeIntervalSince1970: 60),
            source: .manualInterval,
            isCancelled: false
        )
        #expect(
            ForegroundReconcileScheduling.needsTick(
                hasOpenRide: false,
                passengerChrome: .soon(interval)
            )
        )
        #expect(
            ForegroundReconcileScheduling.needsTick(
                hasOpenRide: false,
                passengerChrome: .offer(interval, collapsed: false)
            )
        )
    }
}

@MainActor
struct ForegroundReconcileSessionTests {
    @Test func fixedClockNeverStartsForegroundLoop() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)

        #expect(manager.needsForegroundReconcileTick)
        manager.setForegroundReconcileActive(true)
        #expect(manager.isForegroundForReconcile)
        #expect(manager.foregroundReconcileTask == nil)
    }

    @Test func needsTickFollowsRideAndClearsWhenIdle() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        #expect(!manager.needsForegroundReconcileTick)

        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        #expect(manager.needsForegroundReconcileTick)

        try manager.arrive()
        #expect(!manager.needsForegroundReconcileTick)
        #expect(manager.foregroundReconcileTask == nil)
    }

    @Test func setForegroundInactiveStopsIntentWithoutLoop() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)

        manager.setForegroundReconcileActive(true)
        manager.setForegroundReconcileActive(false)
        #expect(!manager.isForegroundForReconcile)
        #expect(manager.foregroundReconcileTask == nil)
    }
}
