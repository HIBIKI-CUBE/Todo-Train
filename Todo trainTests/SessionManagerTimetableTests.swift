//
//  SessionManagerTimetableTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerTimetableTests {
    @Test func userPauseBeforeStart_createsNoGuard() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 2 * 60 * 60)
        try manager.board(ticket: ticket)
        let start = clock.now.addingTimeInterval(40 * 60)
        insertBlock(context, start: start)

        clock.advance(by: 40 * 60 - 2)
        try manager.pause()

        #expect(manager.fetchTimetableGuards().isEmpty)
        #expect(manager.phase == .paused)
        #expect(manager.timetableQuietMessage == nil)
        #expect(Int(manager.elapsedSeconds.rounded()) == 40 * 60 - 2)
    }

    @Test func atStart_armsGuardAndSchedulesPauseNotice() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(checkInNotifier: checkIns)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 2 * 60 * 60)
        try manager.board(ticket: ticket)
        let start = clock.now.addingTimeInterval(40 * 60)
        insertBlock(context, start: start)

        clock.advance(by: 40 * 60)
        manager.reconcile()

        #expect(manager.phase == .running)
        #expect(manager.fetchTimetableGuards().count == 1)
        #expect(checkIns.timetable.first?.fireAt == start)
        #expect(manager.timetableQuietMessage == nil)
    }

    @Test func afterGrace_pausesAtProtectionBoundary() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 2 * 60 * 60)
        try manager.board(ticket: ticket)
        let start = clock.now.addingTimeInterval(40 * 60)
        insertBlock(context, start: start)

        clock.advance(by: 40 * 60)
        manager.reconcile()
        clock.advance(by: 90)
        manager.reconcile()

        #expect(manager.phase == .paused)
        #expect(Int(manager.elapsedSeconds.rounded()) == 40 * 60 + 60)
        #expect(manager.timetableQuietMessage == TimetableCopy.pausedQuietly)
        let pause = try #require(manager.activeSession?.pauses.first)
        #expect(pause.startedAt == start.addingTimeInterval(60))
    }

    @Test func lateReturnWithoutPriorReconcile_stillPausesAtBoundary() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 2 * 60 * 60)
        try manager.board(ticket: ticket)
        let start = clock.now.addingTimeInterval(40 * 60)
        insertBlock(context, start: start)

        clock.advance(by: 40 * 60 + 30 * 60)
        manager.reconcile()

        #expect(manager.phase == .paused)
        #expect(Int(manager.elapsedSeconds.rounded()) == 40 * 60 + 60)
        #expect(manager.activeSession?.pauses.count == 1)
    }

    @Test func userPauseDuringGrace_isOrdinaryPause() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 2 * 60 * 60)
        try manager.board(ticket: ticket)
        let start = clock.now.addingTimeInterval(40 * 60)
        insertBlock(context, start: start)

        clock.advance(by: 40 * 60)
        manager.reconcile()
        clock.advance(by: 35)
        try manager.pause()

        #expect(manager.phase == .paused)
        #expect(Int(manager.elapsedSeconds.rounded()) == 40 * 60 + 35)
        #expect(manager.timetableQuietMessage == nil)
        let record = try #require(manager.fetchTimetableGuards().first)
        #expect(record.resolvedAt != nil)
        #expect(record.invalidatedAt == nil)
    }

    @Test func boardedDuringBlock_doesNotArm() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let start = clock.now.addingTimeInterval(-120)
        insertBlock(context, start: start)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 2 * 60 * 60)
        try manager.board(ticket: ticket)
        clock.advance(by: 60)
        manager.reconcile()

        #expect(manager.phase == .running)
        #expect(manager.fetchTimetableGuards().isEmpty)
        #expect(manager.timetableQuietMessage == nil)
    }

    @Test func arrivedSession_doesNotCreateRetroPause() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 2 * 60 * 60)
        try manager.board(ticket: ticket)
        let start = clock.now.addingTimeInterval(10 * 60)
        insertBlock(context, start: start)
        clock.advance(by: 5 * 60)
        try manager.arrive()

        clock.advance(by: 20 * 60)
        manager.reconcile()

        #expect(manager.phase == .idle)
        #expect(manager.activeSession == nil)
        #expect(manager.fetchTimetableGuards().allSatisfy { $0.invalidatedAt != nil || $0.resolvedAt != nil })
    }

    @Test func consecutiveBlocks_doNotStackWhilePaused() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 3 * 60 * 60)
        try manager.board(ticket: ticket)
        let first = clock.now.addingTimeInterval(40 * 60)
        insertBlock(context, title: "1on1", start: first)
        insertBlock(context, title: "次", start: first.addingTimeInterval(30 * 60))

        clock.advance(by: 40 * 60 + 90)
        manager.reconcile()
        #expect(manager.phase == .paused)
        #expect(manager.activeSession?.pauses.count == 1)

        clock.advance(by: 30 * 60)
        manager.reconcile()
        #expect(manager.phase == .paused)
        #expect(manager.activeSession?.pauses.count == 1)
    }

    @Test func staleTimetableNotice_doesNotPauseALaterRide() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let first = try SessionManagerFixtures.makeTicket(context, title: "A", seconds: 2 * 60 * 60)
        try manager.board(ticket: first)
        let firstID = try #require(manager.activeSession?.id)
        let start = clock.now.addingTimeInterval(40 * 60)
        insertBlock(context, start: start)
        clock.advance(by: 40 * 60)
        manager.reconcile()
        try manager.pause()
        try manager.arrive()

        let second = try SessionManagerFixtures.makeTicket(context, title: "B", seconds: 2 * 60 * 60)
        try manager.board(ticket: second)
        manager.handleCheckInNotification(
            identifier: CheckInNotification.timetableIdentifier(sessionID: firstID, guardID: firstID),
            action: CheckInNotification.pauseAction
        )
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.title == "B")
    }

    @Test func adoptOccurrence_andSeriesRule_materializeNext() throws {
        let board = NoOpCalendarBoard()
        board.authorization = .authorized
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness(calendarBoard: board)
        let start = clock.now.addingTimeInterval(3600)
        let first = CalendarOccurrence(
            eventIdentifier: "evt-1",
            recurrenceIdentifier: "series-1",
            title: "スタンドアップ",
            startsAt: start,
            endsAt: start.addingTimeInterval(1800),
            isAllDay: false,
            isDeclined: false
        )
        try manager.adoptOccurrence(first, scope: .series)
        #expect(manager.fetchTimetableBlocks().count == 1)

        let next = CalendarOccurrence(
            eventIdentifier: "evt-2",
            recurrenceIdentifier: "series-1",
            title: "スタンドアップ",
            startsAt: start.addingTimeInterval(7 * 86_400),
            endsAt: start.addingTimeInterval(7 * 86_400 + 1800),
            isAllDay: false,
            isDeclined: false
        )
        try manager.refreshCalendarMembership(occurrences: [first, next])
        #expect(manager.fetchTimetableBlocks().filter(\.isActive).count == 2)
    }

    @Test func allDay_isNotAdopted() throws {
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness()
        let start = clock.now
        try manager.adoptOccurrence(
            CalendarOccurrence(
                eventIdentifier: "all",
                recurrenceIdentifier: nil,
                title: "出張",
                startsAt: start,
                endsAt: start.addingTimeInterval(86_400),
                isAllDay: true,
                isDeclined: false
            ),
            scope: .occurrence
        )
        #expect(manager.fetchTimetableBlocks().isEmpty)
    }

    @Test func manualBlock_andUnadopt() throws {
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness()
        let start = clock.now.addingTimeInterval(3600)
        try manager.adoptManualBlock(
            title: "お迎え",
            startsAt: start,
            endsAt: start.addingTimeInterval(1800)
        )
        let block = try #require(manager.fetchTimetableBlocks().first)
        #expect(block.source == .manual)
        #expect(block.title == "お迎え")
        try manager.unadopt(block: block, seriesToo: false)
        #expect(block.isCancelled)
    }

    @Test func endBellFoldsToEarlierTimetableStart() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let start = clock.now.addingTimeInterval(120)
        try manager.adoptManualBlock(
            title: "1on1",
            startsAt: start,
            endsAt: start.addingTimeInterval(1800)
        )
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)

        #expect(scheduler.requests.first?.fireAt == start)
        #expect(scheduler.requests.first?.ticketTitle == "1on1")
    }

    @Test func awayIsSuppressedNearAdoptedBlock() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(checkInNotifier: checkIns)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let start = clock.now.addingTimeInterval(90)
        insertBlock(context, start: start)
        manager.beginAwayWatch()
        #expect(manager.activeSession?.awayDueAt == nil)
        #expect(checkIns.away.isEmpty)
    }

    private func insertBlock(
        _ context: ModelContext,
        title: String = "1on1",
        start: Date
    ) {
        context.insert(
            TimetableBlock(
                title: title,
                startsAt: start,
                endsAt: start.addingTimeInterval(30 * 60),
                source: .manual
            )
        )
        try? context.save()
    }
}
