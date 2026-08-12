//
//  SessionManagerTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionManagerTests {
    private func makeHarness(
        now: Date = Date(timeIntervalSince1970: 1_700_000_000),
        pauseLimit: Int = PauseLimitGuard.defaultLimit,
        endBellEnabled: Bool = false,
        overrideCounter: (any OverrideCounting)? = nil,
        alarmScheduler: InMemoryAlarmScheduler? = nil
    ) throws -> (SessionManager, ModelContext, FixedSessionClock, InMemoryAlarmScheduler) {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(now)
        let settings = AppSettings.makeForTesting(
            pauseLimit: pauseLimit,
            endBellEnabled: endBellEnabled
        )
        let scheduler = alarmScheduler ?? InMemoryAlarmScheduler()
        let manager = SessionManager(
            modelContext: context,
            clock: clock,
            settings: settings,
            overrideCounter: overrideCounter ?? InMemoryOverrideCounter(),
            alarmScheduler: scheduler
        )
        return (manager, context, clock, scheduler)
    }

    private func makeTicket(
        _ context: ModelContext,
        title: String = "A",
        seconds: Int = 1800
    ) throws -> Ticket {
        let ticket = Ticket(title: title, estimatedSeconds: seconds)
        context.insert(ticket)
        try context.save()
        return ticket
    }

    @Test func startService_thenBoard_setsRunning() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == ticket.id)
        #expect(manager.elapsedSeconds >= 0)
    }

    @Test func cannotBoard_withoutService() throws {
        let (manager, context, _, _) = try makeHarness()
        let ticket = try makeTicket(context)

        #expect(throws: SessionError.noActiveService) {
            try manager.board(ticket: ticket)
        }
    }

    @Test func cannotBoard_secondTicket_whileRunning() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")

        try manager.board(ticket: a)

        #expect(throws: SessionError.alreadyBoarding) {
            try manager.board(ticket: b)
        }
    }

    @Test func pause_accumulatesElapsed_andStopsGrowth() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 120)
        manager.reconcile()
        let elapsedBeforePause = manager.elapsedSeconds

        try manager.pause()
        #expect(manager.phase == .paused)
        #expect(elapsedBeforePause == 120)

        clock.advance(by: 300)
        manager.reconcile()
        #expect(manager.elapsedSeconds == 120)
    }

    @Test func resume_continuesFromPaused() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 60)
        try manager.pause()
        clock.advance(by: 100)
        try manager.resume()
        clock.advance(by: 30)
        manager.reconcile()

        #expect(manager.phase == .running)
        #expect(manager.elapsedSeconds == 90)
    }

    @Test func pause_blocked_whenTwoPaused() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)

        try manager.board(ticket: c)
        #expect(manager.phase == .running)

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.pause()
        }
    }

    @Test func pause_allowed_whenLimitIsThree() throws {
        let (manager, context, _, _) = try makeHarness(pauseLimit: 3)
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")
        let d = try makeTicket(context, title: "D")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        try manager.board(ticket: c)
        try manager.pause()
        #expect(manager.pausedTicketCount == 3)

        try manager.board(ticket: d)
        #expect(throws: SessionError.pauseLimitReached) {
            try manager.pause()
        }
    }

    @Test func arrive_closesSessionAndTicket() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)
        clock.advance(by: 10)
        try manager.arrive()

        #expect(manager.phase == .idle)
        #expect(manager.activeSession == nil)
        #expect(ticket.closedAt != nil)
        #expect(ticket.closureKind == .arrived)
        #expect(ticket.sessions.first?.outcome == .arrived)
        #expect(ticket.sessions.first?.endedAt != nil)
    }

    @Test func overtime_whenPastBudget() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 60)

        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()

        #expect(manager.phase == .overtime)
        #expect(manager.remainingSeconds < 0)
    }

    @Test func recoverOnLaunch_restoresOpenSession() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(start)
        let manager = SessionManager(modelContext: context, clock: clock)

        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        clock.advance(by: 45)

        let manager2 = SessionManager(modelContext: context, clock: clock)
        try manager2.recoverOnLaunch()

        #expect(manager2.phase == .running)
        #expect(manager2.activeSession?.ticket?.id == ticket.id)
        #expect(manager2.elapsedSeconds == 45)
    }

    @Test func endService_throwsWhileRunning() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)

        #expect(throws: SessionError.cannotEndServiceWhileRunning) {
            try manager.endService()
        }
    }

    @Test func endService_throwsWithUnresolvedPaused() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        try manager.board(ticket: a)
        try manager.pause()

        #expect(throws: SessionError.unresolvedPausedTickets) {
            try manager.endService()
        }
        #expect(manager.isInService == true)
        #expect(manager.pausedTicketCount == 1)
        #expect(a.isOpen)
    }

    @Test func endService_succeeds_afterResolvingPaused() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        try manager.board(ticket: a)
        try manager.pause()

        let paused = try #require(manager.pausedSessions.first)
        try manager.abandon(session: paused)
        try manager.endService()

        #expect(manager.isInService == false)
        #expect(manager.pausedTicketCount == 0)
        #expect(a.closureKind == .abandoned)
    }

    @Test func startService_throwsWhenPreviousDayStillOpen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(day1)
        let manager = SessionManager(
            modelContext: context,
            clock: clock,
            calendar: calendar,
            settings: AppSettings.makeForTesting()
        )
        try manager.startService()
        #expect(manager.isInService)

        clock.advance(by: day2.timeIntervalSince(day1))
        manager.reconcile()
        #expect(manager.needsServiceDayEndPrompt)

        #expect(throws: SessionError.serviceDayNeedsEnd) {
            try manager.startService()
        }
    }

    @Test func recoverOnLaunch_closesDuplicateOpenServiceDays() throws {
        let (manager, context, clock, _) = try makeHarness()
        let older = ServiceDay(
            startedAt: clock.now.addingTimeInterval(-3600),
            calendarDayKey: "2099-01-01"
        )
        let newer = ServiceDay(
            startedAt: clock.now,
            calendarDayKey: ServiceDay.dayKey(for: clock.now, calendar: .current)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        try manager.recoverOnLaunch()
        #expect(older.endedAt != nil)
        #expect(newer.endedAt == nil)
        #expect(manager.activeServiceDay?.id == newer.id)
    }

    @Test func extend_increasesBudget_andLeavesOvertime() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 60)

        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()
        #expect(manager.phase == .overtime)

        try manager.extend(by: 120)
        manager.reconcile()

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.budgetSecondsAtStart == 180)
        #expect(manager.remainingSeconds > 0)
    }

    @Test func extend_recordsReason() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        try manager.extend(by: 300, reason: "割り込みが入った")

        let session = try #require(manager.activeSession)
        #expect(session.extensions.count == 1)
        #expect(session.extensions.first?.addedSeconds == 300)
        #expect(session.extensions.first?.reason == "割り込みが入った")
    }

    @Test func arrive_recordsOvertimeResolution() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 60)
        try manager.board(ticket: ticket)
        clock.advance(by: 61)
        manager.reconcile()
        try manager.arrive(resolution: .alreadyDone)

        #expect(ticket.sessions.first?.overtimeResolution == .alreadyDone)
        #expect(ticket.closureKind == .arrived)
    }

    @Test func partialDisembark_closesTicketWithPartialKind() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)
        try manager.partialDisembark()

        #expect(manager.phase == .idle)
        #expect(ticket.closureKind == .partialDisembark)
        #expect(ticket.closedAt != nil)
        #expect(ticket.sessions.first?.outcome == .partialDisembark)
    }

    @Test func abandon_closesTicket() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)
        try manager.abandon()

        #expect(manager.phase == .idle)
        #expect(ticket.closureKind == .abandoned)
        #expect(ticket.closedAt != nil)
    }

    @Test func pause_succeeds_afterAbandoningPaused() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)

        try manager.board(ticket: c)
        let pausedA = manager.pausedSessions.first { $0.ticket?.id == a.id }
        #expect(pausedA != nil)
        try manager.abandon(session: pausedA!)

        #expect(manager.pausedTicketCount == 1)
        try manager.pause()
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 2)
    }

    @Test func forcePause_bypassesLimit_andIncrementsCount() throws {
        let counter = InMemoryOverrideCounter()
        let (manager, context, _, _) = try makeHarness(overrideCounter: counter)
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        try manager.board(ticket: c)

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.pause()
        }

        let count = try manager.forcePause()
        #expect(count == 1)
        #expect(manager.todayOverrideCount == 1)
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 3)
    }

    @Test func forcePause_countResetsOnNewDay() throws {
        let counter = InMemoryOverrideCounter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let day1 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12))!
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(day1)
        let manager = SessionManager(
            modelContext: context,
            clock: clock,
            calendar: calendar,
            overrideCounter: counter
        )

        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")
        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        try manager.board(ticket: c)
        _ = try manager.forcePause()
        #expect(manager.todayOverrideCount == 1)

        // New calendar day — count for that day starts at 0.
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9))!
        clock.advance(by: day2.timeIntervalSince(day1))
        let manager2 = SessionManager(
            modelContext: context,
            clock: clock,
            calendar: calendar,
            overrideCounter: counter
        )
        #expect(manager2.todayOverrideCount == 0)
        #expect(counter.count(forDayKey: ServiceDay.dayKey(for: day1, calendar: calendar)) == 1)
        #expect(counter.count(forDayKey: ServiceDay.dayKey(for: day2, calendar: calendar)) == 0)
    }

    @Test func endBell_scheduledWhenEnabledOnBoard() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)

        #expect(scheduler.requests.count == 1)
        #expect(scheduler.requests.first?.ticketTitle == ticket.title)
        #expect(scheduler.requests.first?.sessionID == manager.activeSession?.id)
    }

    @Test func endBell_notScheduledWhenDisabled() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try makeHarness(
            endBellEnabled: false,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)

        #expect(scheduler.requests.isEmpty)
    }

    @Test func endBell_pausedOnPause() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        try manager.pause()

        #expect(scheduler.pausedSessionIDs.contains(sessionID))
        #expect(!scheduler.cancelledSessionIDs.contains(sessionID))
    }

    @Test func endBell_resumedOnResume() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        try manager.pause()
        try manager.resume()

        #expect(scheduler.resumedSessionIDs.contains(sessionID))
    }

    @Test func endBell_rescheduledOnExtend() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
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
        let (manager, context, _, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
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
        let (manager, context, clock, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        manager.suppressEndBell(sessionID: sessionID)
        clock.advance(by: 30)
        try manager.extend(by: 120)

        #expect(scheduler.requests.contains { $0.sessionID == sessionID })
    }

    @Test func pauseFromAlarmKit_forcePausesWhenLimitReached() throws {
        let (manager, context, _, _) = try makeHarness(pauseLimit: 2)
        try manager.startService()
        let a = try makeTicket(context, title: "A", seconds: 600)
        let b = try makeTicket(context, title: "B", seconds: 600)
        let c = try makeTicket(context, title: "C", seconds: 600)

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        try manager.board(ticket: c)
        #expect(manager.pausedTicketCount == 2)
        #expect(manager.phase == .running)

        try manager.pauseFromAlarmKit()
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 3)
        #expect(manager.todayOverrideCount == 1)
    }

    @Test func recoverOnLaunch_keepsPausedEndBell() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        try manager.pause()
        #expect(scheduler.pausedSessionIDs.contains(sessionID))
        let cancelAllBefore = scheduler.cancelAllCount

        try manager.recoverOnLaunch()
        #expect(scheduler.cancelAllCount == cancelAllBefore)
        #expect(manager.phase == .paused)
    }

    @Test func deleteTicket_removesUnusedTicket() throws {
        let (manager, context, _, _) = try makeHarness()
        let ticket = try makeTicket(context, title: "誤作成")
        let id = ticket.id

        try manager.deleteTicket(ticket)

        let remaining = try context.fetch(FetchDescriptor<Ticket>())
        #expect(!remaining.contains { $0.id == id })
    }

    @Test func deleteTicket_whileRunning_clearsActiveSession() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, _, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)

        try manager.deleteTicket(ticket)

        #expect(manager.phase == .idle)
        #expect(manager.activeSession == nil)
        #expect(scheduler.cancelledSessionIDs.contains(sessionID))
        let tickets = try context.fetch(FetchDescriptor<Ticket>())
        #expect(tickets.isEmpty)
        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(sessions.isEmpty)
    }

    @Test func deleteEndedSession_removesRow_andOrphanTicket() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        try manager.arrive()
        let session = try #require(ticket.sessions.first)
        #expect(session.endedAt != nil)

        try manager.deleteEndedSession(session)

        #expect(try context.fetch(FetchDescriptor<WorkSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)
    }

    @Test func deleteEndedSession_keepsTicket_whenOtherSessionsRemain() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()

        let ticket = try makeTicket(context, title: "二区間")
        let first = WorkSession(
            startedAt: clock.now,
            estimatedSecondsAtStart: 600,
            ticket: ticket
        )
        first.endedAt = clock.now.addingTimeInterval(100)
        first.outcome = .arrived
        first.accumulatedActiveSeconds = 100
        first.segmentStartedAt = nil
        context.insert(first)

        let second = WorkSession(
            startedAt: clock.now.addingTimeInterval(200),
            estimatedSecondsAtStart: 600,
            ticket: ticket
        )
        second.endedAt = clock.now.addingTimeInterval(300)
        second.outcome = .arrived
        second.accumulatedActiveSeconds = 100
        second.segmentStartedAt = nil
        context.insert(second)
        ticket.closedAt = clock.now.addingTimeInterval(300)
        ticket.closureKind = .arrived
        try context.save()

        try manager.deleteEndedSession(first)

        let tickets = try context.fetch(FetchDescriptor<Ticket>())
        #expect(tickets.count == 1)
        #expect(tickets.first?.id == ticket.id)
        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == second.id)
    }

    @Test func deleteEndedSession_rejectsOpenSession() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        let session = try #require(manager.activeSession)

        #expect(throws: SessionError.cannotDeleteOpenSession) {
            try manager.deleteEndedSession(session)
        }
    }
}
