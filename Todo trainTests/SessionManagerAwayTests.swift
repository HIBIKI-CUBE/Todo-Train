//
//  SessionManagerAwayTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerAwayTests {
    @Test func beginAwayWatch_unlocked_schedulesDue() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        #expect(manager.activeSession?.awayDueAt != nil)
    }

    @Test func beginAwayWatch_locked_isNoOp() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(deviceLock: FixedDeviceLock(isLocked: true))
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        #expect(manager.activeSession?.awayDueAt == nil)
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func cancelAwayWatch_clearsDue_withoutPromoting() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        manager.cancelAwayWatch()
        #expect(manager.activeSession?.awayDueAt == nil)
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func reconcile_awayDue_setsInterrupt_notFocusQuestion() throws {
        let live = InMemoryLiveActivityManager(areActivitiesEnabled: true)
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            checkInNotifier: checkIns,
            liveActivityManager: live
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        #expect(checkIns.away.isEmpty)
        clock.advance(by: 90)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .away)
        #expect(manager.activeSession?.awayDueAt == nil)
        #expect(live.current?.checkInPrompt == CheckInCopy.away)
        #expect(live.alertCount == 1)
        #expect(checkIns.away.isEmpty)
    }

    @Test func endAwayWatch_clearsAwayInterrupt() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            liveActivityManager: InMemoryLiveActivityManager()
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        clock.advance(by: 90)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .away)
        manager.endAwayWatch()
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.activeSession?.awayDueAt == nil)
    }

    @Test func endBellOn_doesNotScheduleAwayNotification() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            checkInNotifier: checkIns
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        #expect(manager.activeSession?.awayDueAt == nil)
        #expect(checkIns.away.isEmpty)
    }

    @Test func awayNotification_stillOnIt_isIgnored() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            checkInNotifier: checkIns,
            liveActivityManager: NoOpLiveActivityManager()
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        #expect(checkIns.away.count == 1)
        clock.advance(by: 90)
        let identifier = CheckInNotification.awayIdentifier(sessionID: manager.activeSession!.id)
        manager.handleCheckInNotification(
            identifier: identifier,
            action: CheckInNotification.stillOnItAction
        )
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.isPaused == false)
    }

    @Test func awayNotification_pause_stopsTheRide() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            checkInNotifier: checkIns,
            liveActivityManager: NoOpLiveActivityManager()
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        clock.advance(by: 90)
        let identifier = CheckInNotification.awayIdentifier(sessionID: manager.activeSession!.id)
        manager.handleCheckInNotification(
            identifier: identifier,
            action: CheckInNotification.pauseAction
        )
        #expect(manager.phase == .paused)
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func progressDue_dropsAway() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)
        #expect(manager.activeSession?.awayDueAt == nil)
    }

    @Test func board_stampsBoardedDeviceID() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        #expect(manager.activeSession?.boardedDeviceID == "test-device")
        #expect(manager.ownsActiveRide)
        #expect(manager.shouldPresentFocusCover)
    }

    @Test func recoverOnLaunch_remoteDevice_skipsAlarmsAndCheckIns() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, _, scheduler) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            checkInNotifier: checkIns,
            deviceIdentity: FixedDeviceIdentity(id: "phone-a")
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        #expect(!scheduler.requests.isEmpty)
        #expect(!checkIns.progress.isEmpty)

        manager.activeSession?.boardedDeviceID = "phone-b"
        try context.save()
        try manager.recoverOnLaunch()

        #expect(manager.activeSession?.boardedDeviceID == "phone-b")
        #expect(!manager.ownsActiveRide)
        #expect(!manager.shouldPresentFocusCover)
        #expect(manager.phase == .running)
        #expect(scheduler.requests.isEmpty)
        #expect(checkIns.progress.isEmpty)
        #expect(checkIns.away.isEmpty)
    }

    @Test func handleRemoteStoreChange_noopsUnlessConfigured() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, _, scheduler) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            checkInNotifier: checkIns
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        manager.activeSession?.boardedDeviceID = "other-phone"
        try context.save()
        #expect(!manager.ownsActiveRide)
        #expect(!scheduler.requests.isEmpty)

        CloudKitSync.isConfiguredOverride = false
        manager.handleRemoteStoreChange()
        #expect(!scheduler.requests.isEmpty)

        CloudKitSync.isConfiguredOverride = true
        defer { CloudKitSync.isConfiguredOverride = nil }
        manager.handleRemoteStoreChange()
        #expect(scheduler.requests.isEmpty)
        #expect(checkIns.progress.isEmpty)
    }
}
