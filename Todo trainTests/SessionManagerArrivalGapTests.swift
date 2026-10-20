//
//  SessionManagerArrivalGapTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerArrivalGapTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func gap1ThenGap2RingOnDifferentDevices() throws {
        let (manager, _, clock, session) = try stamped(reserve: "報告書")
        manager.iphoneHubVisible = true
        manager.macPipVisible = true
        manager.macAttending = true
        manager.reconcile()

        #expect(manager.arrivalGapBanner == nil)
        #expect(manager.gapCueTick == 0)

        clock.advance(by: 3 * 60)
        manager.reconcile()
        let banner = try #require(manager.arrivalGapBanner)
        #expect(banner.prompt == CabinCopy.readyToBoard(title: "報告書"))
        #expect(banner.holdLamp == false)
        #expect(manager.gapCueTick == 0)
        let first = manager.nudgeSnapFields(now: clock.now)
        #expect(first.nudge?.kind == .gap)
        #expect(first.nudge?.stage == .gap1)
        #expect(first.nudge?.ringSurface == .mac)
        #expect(first.pendingCabin == .gap)
        #expect(first.reserved?.title == "報告書")

        clock.advance(by: 3 * 60)
        manager.reconcile()
        #expect(manager.gapCueTick == 1)
        #expect(manager.arrivalGapBanner?.holdLamp == true)
        let second = manager.nudgeSnapFields(now: clock.now)
        #expect(second.nudge?.stage == .gap2)
        #expect(second.nudge?.ringSurface == .iphone)
        #expect(second.nudge?.firedAt == Int(start.addingTimeInterval(5 + 6 * 60).timeIntervalSince1970))

        clock.advance(by: 1)
        manager.reconcile()
        #expect(manager.arrivalGapBanner == nil)
        #expect(manager.nudgeSnapFields(now: clock.now).nudge == nil)
        #expect(manager.gapCueTick == 1)
        let fired = try #require(manager.fetchWorkSession(id: session)?.nudgeFiredStagesRaw)
        #expect(fired.contains(NudgeGap.gap1.rawValue))
        #expect(fired.contains(NudgeGap.gap2.rawValue))
        #expect(NudgeStage(rawValue: NudgeGap.gap1.rawValue) == nil)
    }

    @Test func jumpingToGap2RingsOnce() throws {
        let (manager, _, clock, _) = try stamped(reserve: nil)
        manager.iphoneHubVisible = true
        manager.macPipVisible = true
        manager.macAttending = true
        clock.advance(by: 6 * 60)
        manager.reconcile()
        #expect(manager.gapCueTick == 1)
        #expect(manager.arrivalGapBanner?.prompt == CabinCopy.idle)
        #expect(manager.arrivalGapBanner?.ticketID == nil)
        #expect(manager.nudgeSnapFields(now: clock.now).nudge?.stage == .gap2)
    }

    @Test func theArrivalScreenWaitsAndAFreshCloseCanStillRing() throws {
        let (manager, _, clock, session) = try stamped(reserve: nil)
        manager.iphoneHubVisible = true
        manager.arrivalScreenOpen = true
        clock.advance(by: 3 * 60)
        manager.reconcile()
        #expect(manager.arrivalGapBanner == nil)
        #expect(manager.gapCueTick == 0)
        #expect(manager.fetchWorkSession(id: session)?.nudgeFiredStagesRaw.isEmpty == true)

        manager.arrivalScreenOpen = false
        manager.reconcile()
        #expect(manager.arrivalGapBanner?.prompt == CabinCopy.idle)
        #expect(manager.gapCueTick == 1)
    }

    @Test func focusDoesNotCueAndASilentTurnDoesNotClaimTheMacLamp() throws {
        let (manager, _, clock, _) = try stamped(reserve: "報告書")
        manager.iphoneHubVisible = false
        manager.macPipVisible = true
        manager.macAttending = true
        clock.advance(by: 6 * 60)
        manager.reconcile()
        #expect(manager.gapCueTick == 0)
        let nudge = try #require(manager.nudgeSnapFields(now: clock.now).nudge)
        #expect(nudge.stage == .gap2)
        #expect(nudge.ringSurface == NudgeRingSurface.none)
    }

    @Test func dismissClosesTheRestOfTheWindow() throws {
        let (manager, _, clock, session) = try stamped(reserve: "報告書")
        manager.iphoneHubVisible = true
        clock.advance(by: 3 * 60)
        manager.reconcile()
        let tick = manager.gapCueTick
        manager.acknowledgeCabinStill()
        #expect(manager.arrivalGapBanner == nil)
        #expect(manager.fetchWorkSession(id: session)?.nudgeFiredStagesRaw.contains("gapClosed") == true)

        clock.advance(by: 3 * 60)
        manager.reconcile()
        #expect(manager.arrivalGapBanner == nil)
        #expect(manager.gapCueTick == tick)
        #expect(manager.nudgeSnapFields(now: clock.now).nudge == nil)
    }

    @Test func boardingCancelsTheRemainingStage() throws {
        let (manager, context, clock, _) = try stamped(reserve: "報告書")
        manager.iphoneHubVisible = true
        clock.advance(by: 3 * 60)
        manager.reconcile()
        let ticket = try #require(manager.reservedNextTicket())
        try manager.board(ticket: ticket)
        #expect(manager.phase != .idle)
        #expect(manager.arrivalGapBanner == nil)

        clock.advance(by: 3 * 60)
        manager.reconcile()
        #expect(manager.arrivalGapBanner == nil)
        #expect(manager.nudgeSnapFields(now: clock.now).nudge?.kind != .gap)
        _ = context
    }

    @Test func aChangedReservationReplacesTheFaceAndKeepsTheClock() throws {
        let (manager, context, clock, _) = try stamped(reserve: "報告書")
        let other = try SessionManagerFixtures.makeTicket(context, title: "別件")
        manager.iphoneHubVisible = true
        manager.macPipVisible = true
        manager.macAttending = true
        clock.advance(by: 3 * 60)
        manager.reconcile()
        let shown = try #require(manager.reservedNextTicket())
        let firedAt = try #require(manager.nudgeSnapFields(now: clock.now).nudge?.firedAt)

        shown.reservedAt = nil
        other.reservedAt = clock.now
        manager.reconcile()
        #expect(manager.arrivalGapBanner?.prompt == CabinCopy.readyToBoard(title: "別件"))
        #expect(manager.nudgeSnapFields(now: clock.now).nudge?.stage == .gap1)
        #expect(manager.nudgeSnapFields(now: clock.now).nudge?.firedAt == firedAt)

        let stale = manager.applyNudgeCommand(board(manager, ticket: shown.id))
        #expect(stale.ok == false)
        #expect(stale.error == .reservationChanged)
        #expect(manager.phase == .idle)

        let live = manager.applyNudgeCommand(board(manager, ticket: other.id))
        #expect(live.ok == true)
        #expect(manager.activeSession?.ticket?.id == other.id)
        #expect(manager.arrivalGapBanner == nil)
    }

    @Test func noReservationRejectsBoardReserved() throws {
        let (manager, _, clock, _) = try stamped(reserve: nil)
        manager.iphoneHubVisible = true
        clock.advance(by: 3 * 60)
        manager.reconcile()
        let ack = manager.applyNudgeCommand(board(manager, ticket: UUID()))
        #expect(ack.ok == false)
        #expect(ack.error == .noReservation)
        #expect(manager.phase == .idle)
    }

    @Test func anOpenPassengerRideHoldsTheGap() throws {
        let (manager, context, clock, _) = try stamped(reserve: nil)
        manager.iphoneHubVisible = true
        clock.advance(by: 3 * 60)
        let passenger = PassengerRide(
            intervalId: "move",
            title: "移動",
            intervalStart: clock.now,
            intervalEnd: clock.now.addingTimeInterval(600),
            boardedAt: clock.now,
            source: .manualInterval
        )
        context.insert(passenger)
        try context.save()
        manager.reconcile()
        #expect(manager.arrivalGapBanner == nil)
        #expect(manager.gapCueTick == 0)

        passenger.endedAt = clock.now
        try context.save()
        manager.reconcile()
        #expect(manager.arrivalGapBanner?.prompt == CabinCopy.idle)
    }

    @Test func saturdayAndAHolidayDoNotOpenTheGap() throws {
        let tokyo = SessionManagerArrivalGapTests.tokyo
        let saturday = tokyo.date(from: DateComponents(year: 2024, month: 1, day: 6, hour: 10))!
        let (quiet, _, clock, _) = try stamped(now: saturday, calendar: tokyo, reserve: "報告書")
        quiet.iphoneHubVisible = true
        clock.advance(by: 3 * 60)
        quiet.reconcile()
        #expect(quiet.arrivalGapBanner == nil)
        #expect(quiet.gapCueTick == 0)

        let newYear = tokyo.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 10))!
        let (holiday, _, holidayClock, _) = try stamped(now: newYear, calendar: tokyo, reserve: nil)
        holiday.iphoneHubVisible = true
        holidayClock.advance(by: 6 * 60)
        holiday.reconcile()
        #expect(holiday.arrivalGapBanner == nil)
    }

    @Test func cabinOffDoesNotOpenTheGap() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            cabinAnnouncementsEnabled: false
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        let rideID = try #require(manager.activeSession?.id)
        try manager.arrive()
        try manager.recordArrivalStamp(sessionID: rideID, action: nil)
        manager.iphoneHubVisible = true
        clock.advance(by: 3 * 60)
        manager.reconcile()
        #expect(manager.arrivalGapBanner == nil)
    }

    private func stamped(
        now: Date? = nil,
        calendar: Calendar = .current,
        reserve title: String?
    ) throws -> (SessionManager, ModelContext, FixedSessionClock, UUID) {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            now: now ?? start,
            calendar: calendar
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "今")
        try manager.board(ticket: ticket)
        if let title {
            let next = try SessionManagerFixtures.makeTicket(context, title: title)
            try manager.reserveNextRide(ticket: next, via: .riding)
        }
        let rideID = try #require(manager.activeSession?.id)
        try manager.arrive()
        clock.advance(by: 5)
        try manager.recordArrivalStamp(sessionID: rideID, action: title == nil ? nil : .nextRide)
        return (manager, context, clock, rideID)
    }

    private func board(_ manager: SessionManager, ticket: UUID) -> CommandPlaintext {
        CommandPlaintext(
            id: UUID(),
            op: .boardReserved,
            sessionId: nil,
            at: Int(manager.clock.now.timeIntervalSince1970),
            ticketId: ticket
        )
    }

    private static var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
}
