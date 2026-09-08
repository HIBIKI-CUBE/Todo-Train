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
        cabinAnnouncementsEnabled: Bool = true,
        overrideCounter: (any OverrideCounting)? = nil,
        alarmScheduler: InMemoryAlarmScheduler? = nil,
        checkInNotifier: (any CheckInNotifying)? = nil,
        deviceIdentity: (any DeviceIdentifying)? = nil
    ) throws -> (SessionManager, ModelContext, FixedSessionClock, InMemoryAlarmScheduler) {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(now)
        let settings = AppSettings.makeForTesting(
            pauseLimit: pauseLimit,
            endBellEnabled: endBellEnabled,
            cabinAnnouncementsEnabled: cabinAnnouncementsEnabled
        )
        let scheduler = alarmScheduler ?? InMemoryAlarmScheduler()
        let manager = SessionManager(
            modelContext: context,
            clock: clock,
            settings: settings,
            checkInNotifier: checkInNotifier ?? NoOpCheckInNotifier(),
            overrideCounter: overrideCounter ?? InMemoryOverrideCounter(),
            alarmScheduler: scheduler,
            deviceIdentity: deviceIdentity ?? FixedDeviceIdentity(id: "test-device")
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

    @Test func pause_recordsInterval_untilResume() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 60)
        try manager.pause()

        let session = try #require(manager.activeSession)
        #expect(session.pauses.count == 1)
        #expect(session.pauses.first?.startedAt == clock.now)
        #expect(session.pauses.first?.endedAt == nil)

        clock.advance(by: 180)
        try manager.resume()

        let pause = try #require(session.pauses.first)
        #expect(pause.endedAt == clock.now)
        #expect(pause.endedAt?.timeIntervalSince(pause.startedAt) == 180)
        #expect(session.pauses.filter { $0.endedAt == nil }.isEmpty)
    }

    @Test func pause_secondInterval_appendsAnotherRecord() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        try manager.pause()
        clock.advance(by: 30)
        try manager.resume()
        clock.advance(by: 20)
        try manager.pause()
        clock.advance(by: 40)
        try manager.resume()

        let session = try #require(manager.activeSession)
        let pauses = session.pauses.sorted { $0.startedAt < $1.startedAt }
        #expect(pauses.count == 2)
        #expect(pauses[0].endedAt?.timeIntervalSince(pauses[0].startedAt) == 30)
        #expect(pauses[1].endedAt?.timeIntervalSince(pauses[1].startedAt) == 40)
    }

    @Test func switchBoard_recordsPauseOnParkedRide() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A", seconds: 600)
        let b = try makeTicket(context, title: "B", seconds: 300)
        try manager.board(ticket: a)
        clock.advance(by: 90)
        try manager.switchBoard(ticket: b)

        let parked = try #require(manager.pausedSessions.first)
        #expect(parked.pauses.count == 1)
        #expect(parked.pauses.first?.endedAt == nil)
        #expect(parked.pauses.first?.startedAt == clock.now)
    }

    @Test func arrive_whilePaused_closesOpenPause() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        clock.advance(by: 30)
        try manager.pause()
        clock.advance(by: 50)
        try manager.arrive()

        let session = try #require(ticket.sessions.first)
        let pause = try #require(session.pauses.first)
        #expect(pause.endedAt == session.endedAt)
        #expect(pause.endedAt?.timeIntervalSince(pause.startedAt) == 50)
    }

    @Test func pause_alwaysAllowed_boardBlockedWhenTwoPaused() throws {
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

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.board(ticket: c)
        }
        try manager.board(ticket: a)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == a.id)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)
        #expect(manager.phase == .paused)
    }

    @Test func board_allowed_whenLimitIsThree() throws {
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

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.board(ticket: d)
        }
    }

    @Test func switchBoard_pausesCurrent_andRunsNew_withoutPausedPhase() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A", seconds: 600)
        let b = try makeTicket(context, title: "B", seconds: 300)

        try manager.board(ticket: a)
        clock.advance(by: 90)
        manager.reconcile()

        try manager.switchBoard(ticket: b)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == b.id)
        #expect(manager.pausedTicketCount == 1)
        #expect(manager.pausedSessions.first?.ticket?.id == a.id)
        #expect(manager.pausedSessions.first?.elapsedSeconds(at: clock.now) == 90)

        clock.advance(by: 40)
        manager.reconcile()
        #expect(manager.elapsedSeconds == 40)
        #expect(manager.pausedSessions.first?.elapsedSeconds(at: clock.now) == 90)
    }

    @Test func switchBoard_blocked_whenPauseLimitReached_keepsCurrentRunning() throws {
        let (manager, context, _, _) = try makeHarness()
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
        #expect(manager.pausedTicketCount == 2)

        #expect(throws: SessionError.pauseLimitReached) {
            try manager.switchBoard(ticket: d)
        }
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == c.id)
        #expect(manager.pausedTicketCount == 2)
    }

    @Test func switchBoard_allowed_whenOneAlreadyPaused() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.switchBoard(ticket: c)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == c.id)
        #expect(manager.pausedTicketCount == 2)
    }

    @Test func switchBoard_toPausedTicket_allowedAtLimit() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        let c = try makeTicket(context, title: "C")

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        try manager.board(ticket: c)
        #expect(manager.pausedTicketCount == 2)

        try manager.switchBoard(ticket: a)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == a.id)
        #expect(manager.pausedTicketCount == 2)
        #expect(manager.pausedSessions.contains { $0.ticket?.id == c.id })
    }

    @Test func switchBoard_sameTicket_isNoOp() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)

        try manager.board(ticket: ticket)
        try manager.switchBoard(ticket: ticket)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == ticket.id)
        #expect(manager.pausedTicketCount == 0)
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

        let pausedA = manager.pausedSessions.first { $0.ticket?.id == a.id }
        #expect(pausedA != nil)
        try manager.abandon(session: pausedA!)

        #expect(manager.pausedTicketCount == 1)
        try manager.board(ticket: c)
        try manager.pause()
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 2)
    }

    @Test func resume_stillAllowedWhenPausedAtLimit() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        let b = try makeTicket(context, title: "B")
        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        try manager.pause()
        #expect(manager.pausedTicketCount == 2)
        try manager.board(ticket: a)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == a.id)
    }

    @Test func forcePause_isJustPause() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let a = try makeTicket(context, title: "A")
        try manager.board(ticket: a)
        let count = try manager.forcePause()
        #expect(count == 0)
        #expect(manager.todayOverrideCount == 0)
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 1)
    }

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
        #expect(scheduler.requests.contains { $0.sessionID == sessionID })
        #expect(!scheduler.cancelledSessionIDs.contains(sessionID))
    }

    @Test func endBell_resumedOnResume() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
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

    @Test func pauseFromAlarmKit_pausesWithoutOverride() throws {
        let (manager, context, _, _) = try makeHarness(pauseLimit: 2)
        try manager.startService()
        let a = try makeTicket(context, title: "A", seconds: 600)
        let b = try makeTicket(context, title: "B", seconds: 600)

        try manager.board(ticket: a)
        try manager.pause()
        try manager.board(ticket: b)
        #expect(manager.pausedTicketCount == 1)
        #expect(manager.phase == .running)

        try manager.pauseFromAlarmKit()
        #expect(manager.phase == .paused)
        #expect(manager.pausedTicketCount == 2)
        #expect(manager.todayOverrideCount == 0)
    }

    @Test func recoverOnLaunch_keepsPausedEndBellWithinRetention() throws {
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

        try manager.recoverOnLaunch()
        #expect(scheduler.requests.contains { $0.sessionID == sessionID })
        #expect(manager.phase == .paused)
    }

    @Test func recoverOnLaunch_dropsPausedLiveActivityAfterRetention() throws {
        let scheduler = InMemoryAlarmScheduler()
        let (manager, context, clock, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)
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
        let (manager, context, _, _) = try makeHarness(
            endBellEnabled: true,
            alarmScheduler: scheduler
        )
        try manager.startService()
        let a = try makeTicket(context, title: "A", seconds: 600)
        let b = try makeTicket(context, title: "B", seconds: 600)
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
        let ticket = try makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)

        #expect(scheduler.requests.count == 1)
        #expect(notifier.scheduledSessionIDs.isEmpty)
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

    @Test func restoreDeletedTicket_afterDelete_returnsTicket() throws {
        let (manager, context, _, _) = try makeHarness()
        let ticket = try makeTicket(context, title: "誤作成")
        let record = DeletionUndo.captureTicket(ticket)
        let id = ticket.id

        try manager.deleteTicket(ticket)
        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)

        try manager.restoreDeletedTicket(record)

        let restored = try context.fetch(FetchDescriptor<Ticket>())
        #expect(restored.contains { $0.id == id })
        #expect(restored.first?.title == "誤作成")
    }

    @Test func restoreDeletedTicket_whileRunning_restoresPhase() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        let id = ticket.id
        let record = DeletionUndo.captureTicket(ticket)

        try manager.deleteTicket(ticket)
        #expect(manager.phase == .idle)

        try manager.restoreDeletedTicket(record)

        #expect(manager.phase == .running)
        #expect(manager.activeSession?.ticket?.id == id)
    }

    @Test func restoreDeletedSession_lastRow_restoresTicket() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, title: "到着済")
        try manager.board(ticket: ticket)
        try manager.arrive()
        let session = try #require(ticket.sessions.first)
        let record = DeletionUndo.captureTicket(ticket)

        try manager.deleteEndedSession(session)
        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)

        try manager.restoreDeletedTicket(record)
        #expect(try context.fetch(FetchDescriptor<Ticket>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<WorkSession>()).count == 1)
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

    @Test func arrive_onTime_enqueuesPunctualityMoment() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()

        let moment = try #require(manager.punctualityMoment)
        #expect(manager.punctualityHapticTick == 0)
        #expect(
            moment.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 600,
                actualSeconds: 560,
                punctuality: .onTime
            )
        )
    }

    @Test func arrive_early_enqueuesArrivalMoment() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 10)
        try manager.arrive()

        let moment = try #require(manager.punctualityMoment)
        #expect(manager.punctualityHapticTick == 0)
        #expect(
            moment.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 600,
                actualSeconds: 10,
                punctuality: .early
            )
        )
    }

    @Test func arrive_overtime_enqueuesArrivalMoment() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 120)

        try manager.board(ticket: ticket)
        clock.advance(by: 180)
        try manager.arrive(resolution: .justFinished)

        let moment = try #require(manager.punctualityMoment)
        #expect(
            moment.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 120,
                actualSeconds: 180,
                punctuality: .late
            )
        )
    }

    @Test func endService_onTimeArrivals_enqueuesServiceMoment() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()
        manager.consumePunctualityMoment()
        #expect(manager.punctualityMoment == nil)

        try manager.endService()
        let moment = try #require(manager.punctualityMoment)
        #expect(moment.kind == .onTimeService)
        #expect(manager.punctualityHapticTick == 1)
    }

    @Test func endService_withoutArrivals_doesNotEnqueueServiceMoment() throws {
        let (manager, _, _, _) = try makeHarness()
        try manager.startService()
        try manager.endService()
        #expect(manager.punctualityMoment == nil)
        #expect(manager.punctualityHapticTick == 0)
    }

    @Test func endService_withEarlyArrival_enqueuesServiceMoment() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 10)
        try manager.arrive()
        manager.consumePunctualityMoment()

        try manager.endService()
        let moment = try #require(manager.punctualityMoment)
        #expect(moment.kind == .onTimeService)
    }

    @Test func endService_withOvertimeArrival_doesNotEnqueueServiceMoment() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 120)

        try manager.board(ticket: ticket)
        clock.advance(by: 180)
        try manager.arrive(resolution: .justFinished)
        manager.consumePunctualityMoment()

        try manager.endService()
        #expect(manager.punctualityMoment == nil)
    }

    @Test func consumePunctualityMoment_doesNotTickHaptic() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()
        // Arrival joy is gesture-owned; enqueue must not fire success haptic.
        #expect(manager.punctualityHapticTick == 0)

        manager.consumePunctualityMoment()
        #expect(manager.punctualityMoment == nil)
        #expect(manager.punctualityHapticTick == 0)
        manager.consumePunctualityMoment()
        #expect(manager.punctualityHapticTick == 0)
    }

    @Test func arriveThenEndService_queuesArrivalThenService() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()
        try manager.endService()

        #expect(manager.punctualityQueue.count == 2)
        #expect(
            manager.punctualityMoment?.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 600,
                actualSeconds: 560,
                punctuality: .onTime
            )
        )
        manager.consumePunctualityMoment()
        #expect(manager.punctualityMoment?.kind == .onTimeService)
    }

    @Test func board_shortTrip_schedulesNoProgressCheckIns() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 10 * 60)
        try manager.board(ticket: ticket)
        #expect(manager.activeSession?.checkInOffsets.isEmpty == true)
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func board_thirtyMinutes_schedulesTwoProgressCheckIns() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offsets = manager.activeSession?.checkInOffsets ?? []
        #expect(offsets.count == 2)
        #expect(offsets[0] < offsets[1])
    }

    @Test func reconcile_firesProgressCheckIn_whenElapsedPassesOffset() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)

        clock.advance(by: max(offset - 1, 0))
        manager.reconcile()
        #expect(manager.pendingCheckIn == nil)

        clock.advance(by: 2)
        manager.reconcile()
        #expect(manager.activeSession?.checkInOffsetSeconds.isEmpty == false)
        #expect(manager.pendingCheckIn == .progress)
        #expect(manager.checkInPromptLine.contains("A"))
    }

    @Test func pause_doesNotFireProgressCheckIn() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        try manager.pause()
        clock.advance(by: offset + 60)
        manager.reconcile()
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.phase == .paused)
    }

    @Test func overtime_clearsPendingCheckIn_andDoesNotRestack() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 15 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)

        clock.advance(by: 15 * 60)
        manager.reconcile()
        #expect(manager.phase == .overtime)
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func answerCheckIn_stillOnIt_clearsPending() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        try manager.answerCheckIn(.stillOnIt)
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.activeSession?.checkInFiredCount == 1)
        #expect(manager.activeSession?.checkInAnswers.count == 1)
        #expect(manager.phase == .running)
    }

    @Test func cabinAnnouncementsOff_doesNotFire() throws {
        let (manager, context, clock, _) = try makeHarness(cabinAnnouncementsEnabled: false)
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = manager.activeSession?.checkInOffsets.first ?? 0
        clock.advance(by: max(offset, 1))
        manager.reconcile()
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func beginAwayWatch_promotesOnEndAfterDue() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        #expect(manager.activeSession?.awayDueAt != nil)

        clock.advance(by: 90)
        manager.endAwayWatch()
        #expect(manager.pendingCheckIn == .away)
        #expect(manager.activeSession?.awayDueAt == nil)
    }

    @Test func progressDue_dropsAway() throws {
        let (manager, context, clock, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        manager.beginAwayWatch()
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)
        #expect(manager.activeSession?.awayDueAt == nil)
    }

    @Test func board_stampsBoardedDeviceID() throws {
        let (manager, context, _, _) = try makeHarness()
        try manager.startService()
        let ticket = try makeTicket(context)
        try manager.board(ticket: ticket)
        #expect(manager.activeSession?.boardedDeviceID == "test-device")
        #expect(manager.ownsActiveRide)
        #expect(manager.shouldPresentFocusCover)
    }

    @Test func recoverOnLaunch_remoteDevice_skipsAlarmsAndCheckIns() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, _, scheduler) = try makeHarness(
            endBellEnabled: true,
            checkInNotifier: checkIns,
            deviceIdentity: FixedDeviceIdentity(id: "phone-a")
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 30 * 60)
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
        let (manager, context, _, scheduler) = try makeHarness(
            endBellEnabled: true,
            checkInNotifier: checkIns
        )
        try manager.startService()
        let ticket = try makeTicket(context, seconds: 30 * 60)
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

