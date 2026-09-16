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
        #expect(manager.activeSession?.timetableHeld == true)
        #expect(manager.pausedCountTowardLimit == 0)
        #expect(manager.pausedTicketCount == 1)
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

    @Test func away_suppressedDuringUnadoptedNotice() async throws {
        let board = InMemoryCalendarBoard()
        board.events = [
            calendarOccurrence(id: "n", calendar: "work", title: "定例", startOffset: -60)
        ]
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            cabinAnnouncementsEnabled: true,
            calendarBoard: board
        )
        try manager.startService()
        await manager.refreshCalendarBoard()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        #expect(manager.activeSession?.awayDueAt == nil)
        #expect(manager.timetableFit().shouldSuppressAway)
    }

    @Test func away_notSuppressedForUpcomingUnadoptedNotice() async throws {
        let board = InMemoryCalendarBoard()
        board.events = [
            calendarOccurrence(id: "n", calendar: "work", title: "定例", startOffset: 600)
        ]
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            cabinAnnouncementsEnabled: true,
            calendarBoard: board
        )
        try manager.startService()
        await manager.refreshCalendarBoard()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        #expect(manager.activeSession?.awayDueAt != nil)
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

        #expect(manager.timetableQuietMessage == nil)
        #expect(manager.activeSession?.timetableHeld == false)
    }

    @Test func resumeWithoutUnadopt_rearmsAndPausesAgain() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 0, duration: 1800)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .paused)

        try manager.resume()
        #expect(manager.phase == .running)
        let armed = try context.fetch(FetchDescriptor<TimetableGuard>()).filter(\.isOpen)
        #expect(armed.count == 1)

        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .paused)
    }

    @Test func unadoptCurrent_whileRunning_letsRideContinue() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 0)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        #expect(try context.fetch(FetchDescriptor<TimetableGuard>()).filter(\.isOpen).count == 1)

        manager.unadoptCurrentOccurrence()
        #expect(manager.fetchActiveTimetableBlocks().isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimetableGuard>()).filter(\.isOpen).isEmpty)

        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .running)
        #expect(manager.timetableQuietMessage == nil)
    }

    @Test func unadoptCurrent_afterAtsPause_resumeDoesNotRearm() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 0, duration: 1800)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .paused)
        #expect(manager.timetableFit().currentBlock != nil)

        manager.unadoptCurrentOccurrence()
        #expect(manager.fetchActiveTimetableBlocks().isEmpty)

        try manager.resume()
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .running)
        #expect(try context.fetch(FetchDescriptor<TimetableGuard>()).filter(\.isOpen).isEmpty)
    }

    @Test func adoptCurrentNoticeThisTime_insertsOccurrence() async throws {
        let board = InMemoryCalendarBoard()
        board.events = [
            calendarOccurrence(id: "n", calendar: "work", title: "定例", startOffset: -60)
        ]
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            calendarBoard: board
        )
        try manager.startService()
        await manager.refreshCalendarBoard()
        #expect(manager.currentUnadoptedNotice()?.title == "定例")
        #expect(manager.fetchActiveTimetableBlocks().isEmpty)

        manager.adoptCurrentNoticeThisTime()
        #expect(manager.fetchActiveTimetableBlocks().map(\.title) == ["定例"])
        #expect(manager.currentUnadoptedNotice() == nil)
        #expect(manager.timetableFit().currentBlock?.title == "定例")
        #expect(manager.timetableFit().currentOccupancy?.title == "定例")
        #expect(manager.timetableFit().currentOccupancy?.isAdopted == true)
    }

    @Test func boardDuringNotice_runsWithoutArming() async throws {
        let board = InMemoryCalendarBoard()
        board.events = [
            calendarOccurrence(id: "n", calendar: "work", title: "定例", startOffset: -60)
        ]
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            calendarBoard: board
        )
        try manager.startService()
        await manager.refreshCalendarBoard()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        #expect(manager.phase == .running)
        #expect(try context.fetch(FetchDescriptor<TimetableGuard>()).isEmpty)
        #expect(manager.timetableFit().currentOccupancy?.title == "定例")
        #expect(manager.timetableFit().currentOccupancy?.isAdopted == false)
        #expect(TimetableFit.dutyLine(fit: manager.timetableFit(), now: start) == "掲示 定例 29分")
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

    @Test func atsHold_doesNotConsumePauseLimit() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 0, duration: 3600)
        let a = try SessionManagerFixtures.makeTicket(context, title: "A", seconds: 1800)
        let b = try SessionManagerFixtures.makeTicket(context, title: "B", seconds: 1800)
        let c = try SessionManagerFixtures.makeTicket(context, title: "C", seconds: 1800)

        try manager.board(ticket: a)
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.activeSession?.timetableHeld == true)
        #expect(manager.pausedCountTowardLimit == 0)

        try manager.board(ticket: b)
        #expect(manager.phase == .running)
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.pausedTicketCount == 2)
        #expect(manager.pausedCountTowardLimit == 0)

        try manager.board(ticket: c)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.title == "C")
    }

    @Test func occupancyEnd_clearsQuietAndHold() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        _ = insertBlock(context, startOffset: 0, duration: 180)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.timetableQuietMessage == TimetableCopy.quiet)
        #expect(manager.activeSession?.timetableHeld == true)

        clock.advance(by: 130)
        manager.reconcile()
        #expect(manager.phase == .paused)
        #expect(manager.timetableQuietMessage == nil)
        #expect(manager.activeSession?.timetableHeld == false)
        #expect(manager.pausedCountTowardLimit == 1)
        #expect(manager.timetableFit().currentOccupancy == nil)
    }

    @Test func fit_upcomingNoticeIsNextOccupancy() async throws {
        let board = InMemoryCalendarBoard()
        board.events = [
            calendarOccurrence(id: "n", calendar: "work", title: "定例", startOffset: 600)
        ]
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            calendarBoard: board
        )
        try manager.startService()
        await manager.refreshCalendarBoard()
        let fit = manager.timetableFit()
        #expect(fit.currentOccupancy == nil)
        #expect(fit.nextOccupancy?.title == "定例")
        #expect(fit.nextOccupancy?.isAdopted == false)
        #expect(TimetableFit.occupancyLines(fit: fit, now: start) == ["次 定例 10分"])
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
