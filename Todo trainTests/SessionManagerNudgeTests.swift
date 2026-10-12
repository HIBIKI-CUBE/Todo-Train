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

        try manager.answerCheckIn(.stillOnIt)
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
        let before = session.budgetSecondsAtStart
        let first = manager.applyNudgeCommand(answer(manager, choice: .willExtend, addSeconds: 600))
        #expect(first.ok == true)
        #expect(session.budgetSecondsAtStart == before + 600)
        let working = try #require(session.extensions.first?.workingSeconds)
        #expect(working > 0)

        let second = manager.applyNudgeCommand(answer(manager, choice: .willExtend, addSeconds: 600))
        #expect(second.ok == true)
        #expect(session.budgetSecondsAtStart == before + 600)
        #expect(session.extensions.count == 1)
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
