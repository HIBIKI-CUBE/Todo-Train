import Foundation
import Testing
@testable import Todo_train

@Suite("Offscreen notification gate")
struct SessionManagerOffscreenTests {
    private let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private var tuesday: Date {
        var parts = DateComponents()
        parts.year = 2024
        parts.month = 1
        parts.day = 9
        parts.hour = 12
        parts.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return Calendar(identifier: .gregorian).date(from: parts)!
    }

    private var newYear: Date {
        var parts = DateComponents()
        parts.year = 2024
        parts.month = 1
        parts.day = 1
        parts.hour = 12
        parts.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return Calendar(identifier: .gregorian).date(from: parts)!
    }

    @Test func focusDoesNotScheduleOvertimeUntilThePhoneLeaves() throws {
        let notifier = InMemoryOvertimeNotifier()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: tuesday,
            calendar: tokyo,
            overtimeNotifier: notifier
        )
        manager.iphoneSceneActive = true
        manager.iphoneFocusVisible = true
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        #expect(notifier.scheduledSessionIDs.isEmpty)
        #expect(
            manager.shouldPresentOffscreenNotification(
                OvertimeSchedule.notificationIdentifier(sessionID: sessionID)
            ) == false
        )

        manager.noteIphoneScene(false)
        #expect(notifier.scheduledSessionIDs == [sessionID])
        #expect(manager.offscreenAssignment(now: manager.clock.now).on == .iphone)
    }

    @Test func macPipSuppressesThePhoneNotification() throws {
        let notifier = InMemoryOvertimeNotifier()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: tuesday,
            calendar: tokyo,
            overtimeNotifier: notifier
        )
        manager.suppressProgressLocalNotifications = true
        manager.macPresenceKnown = true
        manager.macPipVisible = true
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        #expect(notifier.scheduledSessionIDs.isEmpty)
        #expect(manager.offscreenAssignment(now: manager.clock.now).on == .none)
    }

    @Test func unknownPresenceStillSchedulesOnThePhone() throws {
        let notifier = InMemoryOvertimeNotifier()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: tuesday,
            calendar: tokyo,
            overtimeNotifier: notifier
        )
        manager.suppressProgressLocalNotifications = true
        manager.macPresenceKnown = false
        manager.macPipVisible = true
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        #expect(notifier.scheduledSessionIDs.count == 1)
        #expect(manager.offscreenAssignment(now: manager.clock.now).on == .iphone)
    }

    @Test func attendingMacTakesTheFirstTurn() throws {
        let notifier = InMemoryOvertimeNotifier()
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: tuesday,
            calendar: tokyo,
            checkInNotifier: checkIns,
            overtimeNotifier: notifier
        )
        manager.suppressProgressLocalNotifications = true
        manager.macPresenceKnown = true
        manager.macAttending = true
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        #expect(notifier.scheduledSessionIDs.isEmpty)
        #expect(checkIns.progress.isEmpty)
        #expect(manager.offscreenAssignment(now: manager.clock.now).on == .mac)
        manager.beginAwayWatch()
        #expect(checkIns.away.isEmpty)
        #expect(manager.offscreenAssignment(now: manager.clock.now).fireAt != nil)
    }

    @Test func hubHidesIdleAndLeavingSchedulesIt() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(
            now: tuesday,
            calendar: tokyo,
            checkInNotifier: checkIns
        )
        manager.iphoneSceneActive = true
        manager.iphoneHubVisible = true
        try manager.startService()
        #expect(checkIns.idle.isEmpty)
        manager.noteIphoneScene(false)
        #expect(!checkIns.idle.isEmpty)
    }

    @Test func holidayDoesNotScheduleIdle() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness(
            now: newYear,
            calendar: tokyo,
            checkInNotifier: checkIns
        )
        try manager.startService()
        #expect(checkIns.idle.isEmpty)
        let day = try #require(manager.activeServiceDay)
        let delay = CabinIdleScheduling.delay(firedCount: 0, seed: day.id) ?? (20 * 60)
        clock.advance(by: delay + 1)
        manager.reconcile()
        #expect(checkIns.idle.isEmpty)
    }
}
