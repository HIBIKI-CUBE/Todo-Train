//
//  SessionManagerReestimateTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerReestimateTests {
    @Test func commitReestimate_setsBudgetAndAppendsEvent() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 45 * 60)
        try manager.board(ticket: ticket)
        clock.advance(by: 12 * 60)
        manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)

        try manager.commitReestimate(
            mode: .progress,
            progressAnswer: 0.4,
            committedRemainingSeconds: 20 * 60,
            shownBandLowSeconds: 1_000,
            shownBandHighSeconds: 1_200,
            detailsOpened: false,
            promptId: ReestimatePromptID.progressV1
        )

        let session = try #require(manager.activeSession)
        #expect(session.reestimateEvents.filter { $0.undoneAt == nil }.count == 1)
        let active = Int(session.elapsedSeconds(at: clock.now).rounded())
        #expect(session.currentBudgetSeconds == active + 20 * 60)
    }

    @Test func commitReestimate_coalescesIdenticalAnswerWithin60Seconds() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 45 * 60)
        try manager.board(ticket: ticket)
        clock.advance(by: 10 * 60)
        manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)

        try manager.commitReestimate(
            mode: .minutesOnly,
            progressAnswer: nil,
            committedRemainingSeconds: 15 * 60,
            shownBandLowSeconds: nil,
            shownBandHighSeconds: nil,
            detailsOpened: false,
            promptId: ReestimatePromptID.remainingV1
        )
        let budgetAfterFirst = try #require(manager.activeSession?.currentBudgetSeconds)
        manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
        clock.advance(by: 30)
        try manager.commitReestimate(
            mode: .minutesOnly,
            progressAnswer: nil,
            committedRemainingSeconds: 15 * 60,
            shownBandLowSeconds: nil,
            shownBandHighSeconds: nil,
            detailsOpened: false,
            promptId: ReestimatePromptID.remainingV1
        )

        let session = try #require(manager.activeSession)
        #expect(session.reestimateEvents.filter { $0.undoneAt == nil }.count == 1)
        #expect(session.currentBudgetSeconds == budgetAfterFirst)
    }

    @Test func undoReestimate_setsUndoneAtAndRestoresBudget() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let budgetAtBoard = try #require(manager.activeSession?.currentBudgetSeconds)
        clock.advance(by: 5 * 60)
        manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
        try manager.commitReestimate(
            mode: .minutesOnly,
            progressAnswer: nil,
            committedRemainingSeconds: 10 * 60,
            shownBandLowSeconds: nil,
            shownBandHighSeconds: nil,
            detailsOpened: false,
            promptId: ReestimatePromptID.remainingV1
        )
        let eventID = try #require(manager.activeSession?.reestimateEvents.last?.id)

        try manager.undoReestimate(eventID: eventID)

        let session = try #require(manager.activeSession)
        #expect(session.reestimateEvents.first?.undoneAt == clock.now)
        #expect(session.currentBudgetSeconds == budgetAtBoard)
    }

    @Test func undoPauseFromFocus_resumesRideAndMarksPauseUndone() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        try manager.pause()
        let pauseID = try #require(manager.activeSession?.pauses.first(where: { $0.endedAt == nil })?.id)

        try manager.undoPauseFromFocus(pauseID: pauseID)

        #expect(manager.phase == .running)
        let pause = try #require(manager.activeSession?.pauses.first { $0.id == pauseID })
        #expect(pause.undoneAt == clock.now)
    }

    @Test func companionReestimateRecordsSurfaceAndInputThenUndoRemovesIt() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 45 * 60)
        try manager.board(ticket: ticket)
        let budgetAtBoard = try #require(manager.activeSession?.currentBudgetSeconds)
        clock.advance(by: 12 * 60)
        let sessionID = try #require(manager.activeSession?.id)

        let ack = try CompanionCommandApplying.apply(
            reestimateCommand(sessionID: sessionID, at: clock.now),
            sessionManager: manager
        )
        #expect(ack.ok)
        #expect(ack.error == nil)

        let session = try #require(manager.activeSession)
        let event = try #require(session.reestimateEvents.last)
        #expect(event.undoneAt == nil)
        #expect(event.surface == .macPip)
        #expect(event.input == .click)
        #expect(event.mode == .progress)
        #expect(event.trigger == .manual)
        #expect(event.promptId == ReestimatePromptID.progressV1)
        #expect(event.progressAnswer == 0.5)
        #expect(event.committedRemainingSeconds == 20 * 60)
        let active = Int(session.elapsedSeconds(at: clock.now).rounded())
        #expect(session.currentBudgetSeconds == active + 20 * 60)

        let undo = try CompanionCommandApplying.apply(
            CommandPlaintext(
                id: UUID(),
                op: .undoReestimate,
                sessionId: sessionID,
                at: Int(clock.now.timeIntervalSince1970)
            ),
            sessionManager: manager
        )
        #expect(undo.ok)
        let after = try #require(manager.activeSession)
        #expect(after.reestimateEvents.last?.undoneAt == clock.now)
        #expect(after.currentBudgetSeconds == budgetAtBoard)

        let again = try CompanionCommandApplying.apply(
            CommandPlaintext(
                id: UUID(),
                op: .undoReestimate,
                sessionId: sessionID,
                at: Int(clock.now.timeIntervalSince1970)
            ),
            sessionManager: manager
        )
        #expect(!again.ok)
        #expect(again.error == .invalidPayload)
    }

    @Test func companionReestimateRejectsUnknownSurfaceWithoutARecord() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        var command = reestimateCommand(sessionID: sessionID, at: clock.now)
        command.surface = .unknown("watch")

        let ack = try CompanionCommandApplying.apply(command, sessionManager: manager)
        #expect(!ack.ok)
        #expect(ack.error == .invalidPayload)
        #expect(manager.activeSession?.reestimateEvents.isEmpty == true)
    }

    @Test func positionCheck_openReleaseAndClose_recordsNothing() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
        manager.dismissReestimate()

        let session = try #require(manager.activeSession)
        #expect(session.reestimateEvents.isEmpty)
        #expect(manager.reestimateRequest == nil)
    }

    @Test func positionCheck_adjust_recordsV2AndChangesEstimate() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let before = try foldOpenSegment(manager, clock: clock, by: 21 * 60)
        let budgetBefore = before.currentBudgetSeconds
        let luxuryBefore = try #require(ridingLuxury(before))
        manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)

        let active = before.elapsedSeconds(at: clock.now)
        let progress = 0.6
        let remaining = try #require(
            PositionReport.committedRemainingSeconds(activeSeconds: active, progress: progress)
        )
        let projected = try #require(
            PositionReport.projectedTotalSecondsInt(activeSeconds: active, progress: progress)
        )
        try manager.commitReestimate(
            mode: .positionReport,
            progressAnswer: progress,
            committedRemainingSeconds: remaining,
            shownBandLowSeconds: nil,
            shownBandHighSeconds: nil,
            detailsOpened: false,
            promptId: ReestimatePromptID.positionV2,
            declaration: .adjust,
            projectedTotalSeconds: projected
        )

        let session = try #require(manager.activeSession)
        let events = session.reestimateEvents.filter { $0.undoneAt == nil }
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.promptId == ReestimatePromptID.positionV2)
        #expect(event.declaration == .adjust)
        #expect(event.mode == .positionReport)
        #expect(session.currentBudgetSeconds != budgetBefore)
        #expect(session.currentBudgetSeconds == Int(active.rounded()) + remaining)
        let luxuryAfter = try #require(ridingLuxury(session))
        #expect(luxuryBefore == 1.0)
        #expect(luxuryAfter < luxuryBefore)
        #expect(manager.focusUndoOffer?.statusLine?.hasSuffix("着で運転調整") == true)
    }

    @Test func positionCheck_recovery_recordsWithoutChangingEstimateOrSeal() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let before = try foldOpenSegment(manager, clock: clock, by: 21 * 60)
        let budgetBefore = before.currentBudgetSeconds
        let luxuryBefore = try #require(ridingLuxury(before))
        let remaining = Int(before.remainingSeconds(at: clock.now).rounded())
        manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)

        try manager.commitReestimate(
            mode: .positionReport,
            progressAnswer: 0.6,
            committedRemainingSeconds: remaining,
            shownBandLowSeconds: nil,
            shownBandHighSeconds: nil,
            detailsOpened: false,
            promptId: ReestimatePromptID.positionV2,
            declaration: .recovery,
            projectedTotalSeconds: nil
        )

        let session = try #require(manager.activeSession)
        let events = session.reestimateEvents.filter { $0.undoneAt == nil }
        #expect(events.count == 1)
        #expect(events.first?.promptId == ReestimatePromptID.positionV2)
        #expect(events.first?.declaration == .recovery)
        #expect(session.currentBudgetSeconds == budgetBefore)
        #expect(ridingLuxury(session) == luxuryBefore)
        #expect(manager.focusUndoOffer?.statusLine?.hasSuffix("着を目指す回復運転") == true)
    }

    @Test func positionCheck_insideWidthStaysCheck_andFullBecomesFull() {
        let active = TimeInterval(21 * 60)
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: false,
                activeSeconds: active,
                estimatedSecondsAtStart: 30 * 60
            )
        )
        #expect(
            PositionCheckFlow.stageAfterRelease(
                percent: 70,
                activeSeconds: active,
                judgment: judgment
            ) == .check
        )
        #expect(
            PositionCheckFlow.stageAfterRelease(
                percent: 60,
                activeSeconds: active,
                judgment: judgment
            ) == .declare
        )
        #expect(
            PositionCheckFlow.stageAfterRelease(
                percent: 100,
                activeSeconds: active,
                judgment: judgment
            ) == .full
        )
        #expect(
            PositionCheckFlow.stageAfterRelease(
                percent: 0,
                activeSeconds: active,
                judgment: judgment
            ) == .check
        )
    }

    /// 走行中の判定は区間を畳んだ秒を見る。時計だけ進めても判の入力には入らない。
    private func foldOpenSegment(
        _ manager: SessionManager,
        clock: FixedSessionClock,
        by seconds: TimeInterval
    ) throws -> WorkSession {
        clock.advance(by: seconds)
        let session = try #require(manager.activeSession)
        session.closeActiveSegment(at: clock.now)
        session.segmentStartedAt = clock.now
        return session
    }

    private func ridingLuxury(_ session: WorkSession) -> Double? {
        let judgment = Punctuality.judgment(for: session)
        let commits = session.reestimateEvents
            .filter { $0.undoneAt == nil && $0.declaration != .recovery }
            .map {
                PunctualityJudgment.ReestimateCommit(
                    reestimateIndex: $0.reestimateIndex,
                    activeSeconds: $0.activeSeconds,
                    committedRemainingSeconds: $0.committedRemainingSeconds
                )
            }
        return PunctualityPresentation.ridingSealLuxury(judgment: judgment, reestimates: commits)
    }

    private func reestimateCommand(sessionID: UUID, at: Date) -> CommandPlaintext {
        CommandPlaintext(
            id: UUID(),
            op: .reestimate,
            sessionId: sessionID,
            at: Int(at.timeIntervalSince1970),
            progressAnswer: 0.5,
            committedRemainingSeconds: 20 * 60,
            mode: .progress,
            trigger: .manual,
            promptId: ReestimatePromptID.progressV1,
            surface: .macPip,
            input: .click
        )
    }
}
