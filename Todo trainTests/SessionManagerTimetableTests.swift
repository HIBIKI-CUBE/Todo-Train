//
//  SessionManagerTimetableTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionManagerTimetableTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func insertBlock(
        _ context: ModelContext,
        title: String = "週次",
        startOffset: TimeInterval,
        duration: TimeInterval = 1800
    ) -> TimetableBlock {
        let block = TimetableBlock(
            title: title,
            startsAt: start.addingTimeInterval(startOffset),
            endsAt: start.addingTimeInterval(startOffset + duration),
            source: .manual
        )
        context.insert(block)
        try? context.save()
        return block
    }

    @Test func pauseBeforeStart_doesNotArm() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 300)
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        try manager.pause()

        let guards = (try context.fetch(FetchDescriptor<TimetableGuard>()))
        #expect(guards.isEmpty)
        #expect(manager.timetableQuietMessage == nil)
    }

    @Test func overlap_armsThenPausesAtBoundary() throws {
        let notifier = InMemoryCheckInNotifier()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            endBellEnabled: false,
            checkInNotifier: notifier
        )
        try manager.startService()
        let block = insertBlock(context, startOffset: 0)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)

        let armed = try context.fetch(FetchDescriptor<TimetableGuard>())
        #expect(armed.count == 1)
        #expect(armed[0].blockID == block.id)
        #expect(armed[0].protectionBoundary == start.addingTimeInterval(60))
        #expect(notifier.timetable.count == 1)
        #expect(manager.phase == .running)

        clock.advance(by: 61)
        manager.reconcile()

        #expect(manager.phase == .paused)
        #expect(manager.activeSession?.pausedAt == start.addingTimeInterval(60))
        #expect(manager.activeSession?.elapsedSeconds(at: clock.now) == 60)
        #expect(manager.timetableQuietMessage == TimetableCopy.quiet)
        #expect(armed[0].resolvedAt != nil)
    }

    @Test func backgroundRecover_pausesAtBoundary() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 0)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)

        clock.advance(by: 180)
        manager.reconcile()

        #expect(manager.phase == .paused)
        #expect(manager.activeSession?.pausedAt == start.addingTimeInterval(60))
        #expect(manager.timetableQuietMessage == TimetableCopy.quiet)
    }

    @Test func boardDuringAdoptedMeeting_stillArms() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: -600)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        clock.now = start
        try manager.board(ticket: ticket)

        let armed = try context.fetch(FetchDescriptor<TimetableGuard>())
        #expect(armed.count == 1)
        #expect(armed[0].protectionBoundary == start.addingTimeInterval(60))
    }

    @Test func unadopted_doesNotArm() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let block = insertBlock(context, startOffset: 0)
        block.isCancelled = true
        try context.save()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)

        #expect(try context.fetch(FetchDescriptor<TimetableGuard>()).isEmpty)
        #expect(manager.phase == .running)
    }

    @Test func arrived_doesNotRetroactivelyPause() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 0)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        clock.advance(by: 30)
        try manager.arrive()

        clock.advance(by: 200)
        manager.reconcile()

        #expect(manager.phase == .idle)
        let session = try context.fetch(FetchDescriptor<WorkSession>()).first
        #expect(session?.outcome == .arrived)
        #expect(session?.pausedAt == nil)
        let guards = try context.fetch(FetchDescriptor<TimetableGuard>())
        #expect(guards.allSatisfy { $0.invalidatedAt != nil || $0.resolvedAt != nil })
    }

    @Test func consecutiveBlocks_doNotStackWhilePaused() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, title: "A", startOffset: 0, duration: 120)
        _ = insertBlock(context, title: "B", startOffset: 120, duration: 1800)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)

        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .paused)

        clock.advance(by: 80)
        manager.reconcile()
        let open = try context.fetch(FetchDescriptor<TimetableGuard>()).filter(\.isOpen)
        #expect(open.isEmpty)
        #expect(manager.phase == .paused)
    }

    @Test func endBell_usesEarlierOfBudgetAndNextBlock() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        _ = insertBlock(context, startOffset: 300, duration: 1800)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)

        #expect(scheduler.requests.count == 1)
        #expect(scheduler.requests.first?.fireAt == start.addingTimeInterval(300))
    }

    @Test func away_suppressedNearBlock() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            cabinAnnouncementsEnabled: true
        )
        try manager.startService()
        _ = insertBlock(context, startOffset: 90)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()

        #expect(manager.activeSession?.awayDueAt == nil)
    }

    @Test func resume_clearsQuietMessage() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 0)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.timetableQuietMessage == TimetableCopy.quiet)

        try manager.resume()
        #expect(manager.timetableQuietMessage == nil)
    }

    @Test func refresh_filtersNoticesBySelectedCalendars() async throws {
        let board = InMemoryCalendarBoard()
        board.calendars = [
            CalendarSource(identifier: "work", title: "仕事"),
            CalendarSource(identifier: "personal", title: "個人")
        ]
        board.events = [
            calendarOccurrence(id: "w", calendar: "work", title: "週次"),
            calendarOccurrence(id: "p", calendar: "personal", title: "歯医者")
        ]
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            calendarBoard: board
        )
        manager.settings.timetableVisibleCalendarIDs = ["work"]
        await manager.refreshCalendarBoard()
        #expect(manager.noticeOccurrences.map(\.title) == ["週次"])
    }

    @Test func hideCalendar_doesNotUnadopt() async throws {
        let board = InMemoryCalendarBoard()
        board.events = [calendarOccurrence(id: "w", calendar: "work", title: "週次")]
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            calendarBoard: board
        )
        await manager.refreshCalendarBoard()
        manager.adoptOccurrence(board.events[0], scope: .occurrence)
        #expect(manager.fetchActiveTimetableBlocks().count == 1)

        manager.settings.timetableVisibleCalendarIDs = []
        await manager.refreshCalendarBoard()
        #expect(manager.fetchActiveTimetableBlocks().count == 1)
        #expect(manager.noticeOccurrences.isEmpty)
    }

    @Test func boardingConflict_adoptedNowAndNoticeNow() async throws {
        let board = InMemoryCalendarBoard()
        board.events = [
            calendarOccurrence(id: "n", calendar: "work", title: "定例", startOffset: -60)
        ]
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            calendarBoard: board
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)

        await manager.refreshCalendarBoard()
        #expect(manager.boardingConflict(for: ticket) == .noticeNow(title: "定例"))

        _ = insertBlock(context, title: "週次", startOffset: -300)
        #expect(manager.boardingConflict(for: ticket) == .adoptedNow(title: "週次"))
    }

    @Test func boardingConflict_adoptedSoonOnlyInsideEstimate() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, title: "1on1", startOffset: 600)
        let longTicket = try SessionManagerFixtures.makeTicket(context, title: "long", seconds: 1800)
        let shortTicket = try SessionManagerFixtures.makeTicket(context, title: "short", seconds: 300)
        #expect(manager.boardingConflict(for: longTicket) == .adoptedSoon(title: "1on1"))
        #expect(manager.boardingConflict(for: shortTicket) == nil)
    }

    private func calendarOccurrence(
        id: String,
        calendar: String,
        title: String,
        startOffset: TimeInterval = 0,
        duration: TimeInterval = 1800
    ) -> CalendarOccurrence {
        CalendarOccurrence(
            eventIdentifier: id,
            title: title,
            startsAt: start.addingTimeInterval(startOffset),
            endsAt: start.addingTimeInterval(startOffset + duration),
            isAllDay: false,
            isDeclined: false,
            calendarIdentifier: calendar,
            calendarTitle: calendar
        )
    }
}
