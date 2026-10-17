//
//  SessionManagerNudgeTests.swift
//  Todo trainTests
//

import Foundation
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerNudgeTests {
    @Test func oneCheckInLandsInTheLateBandAndDoesNotRepeat() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        let band = try #require(NudgePlanner.checkInBand(estimatedSeconds: 30 * 60))
        #expect(band.contains(offset))

        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)
        #expect(manager.activeSession?.nudgeFiredStagesRaw == [NudgeStage.checkIn.rawValue])
        let fired = try #require(manager.activeSession?.nudgeEvents.first)
        #expect(fired.stage == NudgeStage.checkIn.rawValue)
        #expect(fired.rang == false)
        #expect(fired.skipped == true)

        try manager.answerCheckIn(.stillOnIt)
        let stamp = try #require(manager.activeSession?.checkInAnswers.last)
        #expect(stamp.kind == .progress)
        #expect(stamp.answeredStage == NudgeStage.checkIn.rawValue)
        #expect(stamp.answeredOn == "iphone")
        clock.advance(by: 20 * 60)
        manager.reconcile()
        let checkIns = manager.activeSession?.nudgeFiredStagesRaw.filter { $0 == NudgeStage.checkIn.rawValue }
        #expect(checkIns == [NudgeStage.checkIn.rawValue])
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func pauseDoesNotAdvanceStages() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        try manager.pause()
        clock.advance(by: offset + 120)
        manager.reconcile()
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.activeSession?.nudgeFiredStagesRaw.isEmpty == true)
    }

    @Test func relaunchKeepsFiredStagesAndPending() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)

        let resumed = SessionManager(
            modelContext: context,
            clock: clock,
            settings: manager.settings,
            deviceIdentity: FixedDeviceIdentity(id: "test-device")
        )
        try resumed.recoverOnLaunch()
        #expect(resumed.pendingCheckIn == .progress)
        #expect(resumed.activeSession?.nudgeFiredStagesRaw == [NudgeStage.checkIn.rawValue])
    }

    @Test func iphoneAnswerThenADifferentMacCommandIsStale() throws {
        let manager = try rideAtCheckIn()
        try manager.answerCheckIn(.stillOnIt)
        let ack = manager.applyNudgeCommand(answer(manager, choice: .alreadyDone, addSeconds: nil))
        #expect(ack.ok == false)
        #expect(ack.error == .nudgeStale)
        #expect(manager.phase != .idle)
    }

    @Test func sameWillExtendIsANoOp() throws {
        let manager = try rideAtCheckIn()
        let session = try #require(manager.activeSession)
        let before = session.activeBudgetSeconds
        let first = manager.applyNudgeCommand(answer(manager, choice: .willExtend, addSeconds: 600))
        #expect(first.ok == true)
        #expect(session.activeBudgetSeconds == before)
        #expect(session.extensions.isEmpty)
        #expect(manager.reestimateRequest?.remoteWillExtendReceived == true)

        let second = manager.applyNudgeCommand(answer(manager, choice: .willExtend, addSeconds: 600))
        #expect(second.ok == true)
        #expect(session.activeBudgetSeconds == before)
        #expect(session.extensions.isEmpty)
    }

    @Test func extendStoresWorkingSecondsSoAFiredCheckInStaysPut() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        try manager.extend(by: 600)
        let working = try #require(manager.activeSession?.extensions.first?.workingSeconds)
        #expect(abs(working - (offset + 1)) < 2)

        try manager.pause()
        clock.advance(by: 60 * 60)
        try manager.resume()
        manager.reconcile()
        let plan = manager.nudgeSnapFields(now: clock.now).plan ?? []
        #expect(plan.contains { $0.stage == .checkIn } == false)
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.activeSession?.nudgeFiredStagesRaw.contains(NudgeStage.checkIn.rawValue) == true)
    }

    @Test func macExtendStoresWorkingSecondsAtThatMoment() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        try manager.pause()
        clock.advance(by: 80)
        try manager.resume()
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        let ack = manager.applyNudgeCommand(answer(manager, choice: .willExtend, addSeconds: 600))
        #expect(ack.ok == true)
        #expect(manager.activeSession?.extensions.isEmpty == true)
        #expect(manager.reestimateRequest != nil)

        try manager.pause()
        clock.advance(by: 60 * 60)
        try manager.resume()
        #expect(manager.activeSession?.extensions.isEmpty == true)
    }

    @Test func macExtendClosesTheIphonePromptAndUpdatesTheRide() throws {
        let live = InMemoryLiveActivityManager()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(liveActivityManager: live)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)
        #expect(live.current?.checkInPrompt != nil)
        let before = try #require(manager.activeSession?.activeBudgetSeconds)

        let ack = manager.applyNudgeCommand(answer(manager, choice: .willExtend, addSeconds: 600))
        #expect(ack.ok == true)
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.activeBudgetSeconds == before)
        #expect(manager.reestimateRequest != nil)
        #expect(manager.activeSession?.checkInFiredCount == 1)
        #expect(manager.activeSession?.checkInAnswers.count == 1)
        #expect(live.current?.checkInPrompt == nil)
        expectMacQuestionClosed(manager, now: clock.now)
    }

    @Test func answeredPromptStillReturnsToTheRide() throws {
        let manager = try rideAtCheckIn()
        let session = try #require(manager.activeSession)
        let before = session.activeBudgetSeconds
        let ack = manager.applyNudgeCommand(answer(manager, choice: .willExtend, addSeconds: 600))
        #expect(ack.ok == true)
        session.pendingCheckIn = .progress

        try manager.answerCheckIn(.stillOnIt)
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.phase == .running)
        #expect(session.activeBudgetSeconds == before)
        #expect(session.extensions.isEmpty)
        #expect(session.checkInAnswers.count == 1)
        #expect(session.checkInFiredCount == 1)
        expectMacQuestionClosed(manager, now: manager.clock.now)
    }

    @Test func iphoneStillClosesTheMacQuestion() throws {
        let manager = try rideAtCheckIn()
        try manager.answerCheckIn(.stillOnIt)
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.activeSession?.checkInFiredCount == 1)
        expectMacQuestionClosed(manager, now: manager.clock.now)
    }

    @Test func iphoneWillExtendClosesTheMacQuestion() throws {
        let manager = try rideAtCheckIn()
        try manager.answerCheckIn(.willExtend)
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.phase == .running)
        #expect(manager.activeSession?.checkInAnswers.last?.answer == .willExtend)
        expectMacQuestionClosed(manager, now: manager.clock.now)
    }

    @Test func standingPauseRecordsTheOpenNudge() throws {
        let manager = try rideAtCheckIn()
        try manager.pause()
        let stamp = try #require(manager.activeSession?.checkInAnswers.last)
        #expect(stamp.answer == .paused)
        #expect(stamp.answeredOn == "iphone")
        #expect(stamp.nudgeID != nil)
    }

    @Test func iphoneRingFiresOnceOnAFreshHandoff() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        manager.iphoneSceneActive = true
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let handoff = NudgePlanner.marks(estimatedSeconds: 30 * 60, rideID: manager.activeSession!.id)
            .first { $0.stage == .handoff2 }
        let offset = try #require(handoff?.offset)
        clock.advance(by: offset - 1)
        manager.reconcile()
        #expect(manager.nudgeRingTick == 0)
        clock.advance(by: 1)
        manager.reconcile()
        #expect(manager.nudgeRingTick == 1)
        manager.reconcile()
        #expect(manager.nudgeRingTick == 1)
    }

    private func expectMacQuestionClosed(_ manager: SessionManager, now: Date) {
        let snap = RideWireSnap.make(
            sessionManager: manager,
            settings: manager.settings,
            rev: 1,
            now: now
        )
        #expect(snap.nudge == nil)
        #expect(snap.pendingCabin == nil)
        let view = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: snap,
                now: Int(now.timeIntervalSince1970)
            )
        )
        #expect(!view.showsNudgeChoices)
        #expect(view.nudgePrompt == nil)
        #expect(view.cabinPrompt == nil)
    }

    private func rideAtCheckIn() throws -> SessionManager {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        return manager
    }

    private func answer(
        _ manager: SessionManager,
        choice: NudgeChoice,
        addSeconds: Int?
    ) -> CommandPlaintext {
        let session = manager.activeSession!
        return CommandPlaintext(
            id: UUID(),
            op: .answer,
            sessionId: session.id,
            at: Int(manager.clock.now.timeIntervalSince1970),
            nudgeId: NudgeSession.id(sessionID: session.id, stage: .checkIn),
            choice: choice,
            addSeconds: addSeconds,
            answeredOn: .mac
        )
    }
}
