//
//  LiveActivityEndTests.swift
//  Todo trainTests
//
//  下車・運行終了・削除・再起動のあとに Live Activity が残らない。
//

import Foundation
import Testing
@testable import Todo_train

@MainActor
struct LiveActivityEndTests {
    @Test func blankTitleDoesNotPresent() {
        let blank = LiveActivitySessionContent(
            sessionID: UUID(),
            title: "   ",
            deadline: Date(timeIntervalSince1970: 1_700_003_600),
            isOvertime: false,
            budgetSeconds: 600
        )
        let titled = LiveActivitySessionContent(
            sessionID: UUID(),
            title: "仕様書",
            deadline: blank.deadline,
            isOvertime: false,
            budgetSeconds: 600
        )
        #expect(!LiveActivityLifecycle.shouldPresent(blank))
        #expect(LiveActivityLifecycle.shouldPresent(titled))
    }

    @Test func boardingABlankTitleEndsInsteadOfShowing() throws {
        let live = InMemoryLiveActivityManager()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(liveActivityManager: live)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "   ", seconds: 600)
        try manager.board(ticket: ticket)
        #expect(manager.phase == .running)
        #expect(live.current == nil)
        #expect(live.endCount >= 1)
    }

    @Test func partialDisembarkEndsTheLiveActivity() throws {
        let live = try ride()
        try live.manager.partialDisembark()
        #expect(live.manager.phase == .idle)
        #expect(live.activity.current == nil)
        #expect(live.activity.endCount >= 1)
    }

    @Test func endServiceEndsTheLiveActivity() throws {
        let live = try ride()
        try live.manager.arrive()
        try live.manager.endService()
        #expect(live.manager.phase == .idle)
        #expect(live.activity.current == nil)
        #expect(live.activity.endCount >= 1)
    }

    @Test func deletingTheOpenTicketEndsTheLiveActivity() throws {
        let live = try ride()
        let ticket = try #require(live.manager.activeSession?.ticket)
        try live.manager.deleteTicket(ticket)
        #expect(live.manager.phase == .idle)
        #expect(live.activity.current == nil)
        #expect(live.activity.endCount >= 1)
    }

    @Test func recoverOnLaunchEndsAnOrphanLiveActivity() throws {
        let live = InMemoryLiveActivityManager()
        live.startOrUpdate(
            LiveActivitySessionContent(
                sessionID: UUID(),
                title: "残っている",
                deadline: Date(timeIntervalSince1970: 1_700_003_600),
                isOvertime: false,
                budgetSeconds: 600
            )
        )
        #expect(live.current != nil)
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(liveActivityManager: live)
        try manager.recoverOnLaunch()
        #expect(manager.phase == .idle)
        #expect(live.current == nil)
        #expect(live.endCount >= 1)
    }

    @Test func recoverOnLaunchKeepsAPausedLiveActivityInsideRetention() throws {
        let live = try ride()
        try live.manager.pause()
        #expect(live.activity.current != nil)
        let endsBefore = live.activity.endCount
        try live.manager.recoverOnLaunch()
        #expect(live.manager.phase == .paused)
        #expect(live.activity.current != nil)
        #expect(live.activity.endCount == endsBefore)
    }

    @Test func recoverOnLaunchEndsAPausedLiveActivityAfterRetention() throws {
        let live = try ride()
        try live.manager.pause()
        live.clock.advance(by: PauseLiveActivityRetention.maxDuration + 1)
        try live.manager.recoverOnLaunch()
        #expect(live.manager.phase == .paused)
        #expect(live.activity.current == nil)
        #expect(live.activity.endCount >= 1)
    }

    @Test func relaunchCancelsSystemAlarmsThatAreNoLongerTracked() {
        let system = UUID()
        let kept = UUID()
        let ended = AlarmCancellation.ids(tracked: [], system: [system], keep: nil)
        #expect(ended == [system])
        let stillRiding = AlarmCancellation.ids(tracked: [], system: [system, kept], keep: kept)
        #expect(stillRiding == [system])
    }

    private struct Ride {
        var manager: SessionManager
        var activity: InMemoryLiveActivityManager
        var clock: FixedSessionClock
    }

    private func ride() throws -> Ride {
        let activity = InMemoryLiveActivityManager()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(liveActivityManager: activity)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "仕様書", seconds: 600)
        try manager.board(ticket: ticket)
        #expect(activity.current != nil)
        return Ride(manager: manager, activity: activity, clock: clock)
    }
}
