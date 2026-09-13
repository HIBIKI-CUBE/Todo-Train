//
//  SessionManagerEndBellTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerEndBellTests {
    @Test func endBell_scheduledWhenEnabledOnBoard() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)

        #expect(scheduler.requests.count == 1)
        #expect(scheduler.requests.first?.ticketTitle == ticket.title)
        #expect(scheduler.requests.first?.sessionID == manager.activeSession?.id)
    }

    @Test func endBell_notScheduledWhenDisabled() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: false,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)

        #expect(scheduler.requests.isEmpty)
    }

    @Test func endBell_pausedOnPause() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        try manager.pause()

        #expect(scheduler.pausedSessionIDs.contains(sessionID))
        #expect(scheduler.requests.contains { $0.sessionID == sessionID })
        #expect(!scheduler.cancelledSessionIDs.contains(sessionID))
    }

    @Test func endBell_resumedOnResume() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        try manager.pause()
        #expect(scheduler.pausedSessionIDs.contains(sessionID))
        clock.advance(by: 60)
        try manager.resume()

        #expect(scheduler.resumedSessionIDs.contains(sessionID))
        #expect(!scheduler.pausedSessionIDs.contains(sessionID))
        #expect(scheduler.requests.contains { $0.sessionID == sessionID })
    }

    @Test func endBell_rescheduledOnExtend() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let firstFire = try #require(scheduler.requests.first?.fireAt)
        clock.advance(by: 60)
        try manager.extend(by: 300)

        #expect(scheduler.requests.count == 1)
        let secondFire = try #require(scheduler.requests.first?.fireAt)
        #expect(secondFire > firstFire)
    }

    @Test func endBell_suppressPreventsReschedule() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        #expect(scheduler.requests.count == 1)

        manager.suppressEndBell(sessionID: sessionID)
        #expect(scheduler.cancelledSessionIDs.contains(sessionID))

        // Simulate recover / refresh path
        try manager.recoverOnLaunch()
        #expect(scheduler.requests.isEmpty)
        #expect(manager.phase == .running)
    }

    @Test func endBell_extendClearsSuppressAndReschedules() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        manager.suppressEndBell(sessionID: sessionID)
        clock.advance(by: 30)
        try manager.extend(by: 120)

        #expect(scheduler.requests.contains { $0.sessionID == sessionID })
    }

    @Test func pauseFromAlarmKit_pausesWithoutOverride() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(pauseLimit: 2)
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A", seconds: 600)
        let b = try SessionManagerFixtures.makeTicket(context, title: "B", seconds: 600)

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        #expect(manager.pausedTicketCount == 1)
        #expect(manager.phase == .running)

        try manager.pauseFromAlarmKit()
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 2)
    }

    @Test func recoverOnLaunch_keepsPausedEndBellWithinRetention() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        try manager.pause()
        #expect(scheduler.pausedSessionIDs.contains(sessionID))

        try manager.recoverOnLaunch()
        #expect(scheduler.requests.contains { $0.sessionID == sessionID })
        #expect(manager.phase == .paused)
    }

    @Test func recoverOnLaunch_dropsPausedLiveActivityAfterRetention() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        try manager.pause()
        clock.advance(by: PauseLiveActivityRetention.maxDuration + 1)
        try manager.recoverOnLaunch()
        #expect(scheduler.cancelledSessionIDs.contains(sessionID))
        #expect(scheduler.requests.isEmpty)
        #expect(manager.phase == .paused)
    }

    @Test func board_cancelsPreviousPausedEndBell() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let a = try SessionManagerFixtures.makeTicket(context, title: "A", seconds: 600)
        let b = try SessionManagerFixtures.makeTicket(context, title: "B", seconds: 600)
        try manager.board(ticket: a)
        let firstID = try #require(manager.activeSession?.id)
        try manager.pause()
        try manager.board(ticket: b)
        let secondID = try #require(manager.activeSession?.id)
        #expect(scheduler.cancelledSessionIDs.contains(firstID))
        #expect(scheduler.requests.contains { $0.sessionID == secondID })
        #expect(!scheduler.requests.contains { $0.sessionID == firstID })
    }

    @Test func endBell_skipsLocalOvertimeNotificationWhenAuthorized() throws {
        let scheduler = InMemoryAlarmScheduler()
        scheduler.isAuthorized = true
        let notifier = InMemoryOvertimeNotifier()
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(Date(timeIntervalSince1970: 1_700_000_000))
        let settings = AppSettings.makeForTesting(endBellEnabled: true)
        let manager = SessionManager(
            modelContext: context,
            clock: clock,
            settings: settings,
            overtimeNotifier: notifier,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)

        #expect(scheduler.requests.count == 1)
        #expect(notifier.scheduledSessionIDs.isEmpty)
    }
}
