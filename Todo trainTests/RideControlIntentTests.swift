//
//  RideControlIntentTests.swift
//  Todo trainTests
//
//  コントロールの Intent は、画面のボタンと同じ記録を残す。
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct RideControlIntentTests {
    @Test func boardReservedMatchesTheHubButton() async throws {
        let button = try gap(reserve: "報告書")
        try button.manager.boardReservedFromHub()
        let intent = try gap(reserve: "報告書")
        try await perform(intent.manager) {
            _ = try await BoardReservedRideIntent().perform()
        }
        let boarded = try ledger(intent.manager, intent.activity)
        let pressed = try ledger(button.manager, button.activity)
        #expect(boarded == pressed)
    }

    @Test func boardReservedWithoutATicketDoesNotAddARide() async throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let before = try context.fetchCount(FetchDescriptor<WorkSession>())
        try await perform(manager) {
            _ = try await BoardReservedRideIntent().perform()
        }
        let after = try context.fetchCount(FetchDescriptor<WorkSession>())
        #expect(after == before)
        #expect(manager.phase == .idle)
    }

    @Test func continueMatchesTheCheckInButton() async throws {
        let button = try tryProgress()
        try button.manager.answerCheckIn(.stillOnIt)
        let intent = try tryProgress()
        try await perform(intent.manager) {
            _ = try await ContinueRideIntent().perform()
        }
        let continued = try ledger(intent.manager, intent.activity)
        let pressed = try ledger(button.manager, button.activity)
        #expect(continued == pressed)
    }

    @Test func pauseMatchesTheFocusButton() async throws {
        let button = try running(seconds: 10 * 60)
        try button.manager.pause()
        let intent = try running(seconds: 10 * 60)
        try await perform(intent.manager) {
            _ = try await PauseRideIntent().perform()
        }
        let paused = try ledger(intent.manager, intent.activity)
        let pressed = try ledger(button.manager, button.activity)
        #expect(paused == pressed)
    }

    @Test func pauseDuringCheckInMatchesThatButton() async throws {
        let button = try tryProgress()
        try button.manager.answerCheckIn(.paused)
        let intent = try tryProgress()
        try await perform(intent.manager) {
            _ = try await PauseRideIntent().perform()
        }
        let paused = try ledger(intent.manager, intent.activity)
        let pressed = try ledger(button.manager, button.activity)
        #expect(paused == pressed)
    }

    @Test func resumeMatchesThePausedTicketButton() async throws {
        let button = try running(seconds: 10 * 60)
        try button.manager.pause()
        let ticket = try #require(button.manager.activeSession?.ticket)
        try button.manager.board(ticket: ticket)
        let intent = try running(seconds: 10 * 60)
        try intent.manager.pause()
        try await perform(intent.manager) {
            _ = try await ResumeRideIntent().perform()
        }
        let resumed = try ledger(intent.manager, intent.activity)
        let pressed = try ledger(button.manager, button.activity)
        #expect(resumed == pressed)
    }

    @Test func arriveMatchesTheFocusButtonAndEndsTheLiveActivity() async throws {
        let button = try running(seconds: 10 * 60)
        try button.manager.arrive()
        let intent = try running(seconds: 10 * 60)
        #expect(intent.activity.current != nil)
        try await perform(intent.manager) {
            _ = try await ArriveRideIntent().perform()
        }
        let intentLedger = try ledger(intent.manager, intent.activity)
        let pressed = try ledger(button.manager, button.activity)
        #expect(intentLedger == pressed)
        #expect(intentLedger.activityCurrent == false)
        #expect(intentLedger.activityEndCount >= 1)
        #expect(intent.manager.phase == .idle)
    }

    @Test func idleContinuePauseAndArriveDoNotAddRecords() async throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let sessions = try context.fetchCount(FetchDescriptor<WorkSession>())
        let pauses = try context.fetchCount(FetchDescriptor<SessionPause>())
        try await perform(manager) {
            _ = try await ContinueRideIntent().perform()
            _ = try await PauseRideIntent().perform()
            _ = try await ArriveRideIntent().perform()
            _ = try await ResumeRideIntent().perform()
        }
        let sessionsAfter = try context.fetchCount(FetchDescriptor<WorkSession>())
        let pausesAfter = try context.fetchCount(FetchDescriptor<SessionPause>())
        #expect(sessionsAfter == sessions)
        #expect(pausesAfter == pauses)
        #expect(manager.phase == .idle)
    }

    private struct Harness {
        var manager: SessionManager
        var activity: InMemoryLiveActivityManager
    }

    private struct Ledger: Equatable {
        var phase: SessionPhase
        var rows: [Row]
        var activityEndCount: Int
        var activityCurrent: Bool
    }

    private struct Row: Equatable {
        var title: String
        var open: Bool
        var outcome: String?
        var ended: Bool
        var pauses: [PauseRow]
        var answers: [AnswerRow]
    }

    private struct PauseRow: Equatable {
        var ended: Bool
        var heldBy: String?
        var pausedOn: String?
    }

    private struct AnswerRow: Equatable {
        var kind: String
        var answer: String
        var answeredOn: String?
        var answeredStage: String?
    }

    private func running(seconds: Int) throws -> Harness {
        let activity = InMemoryLiveActivityManager()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(liveActivityManager: activity)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: seconds)
        try manager.board(ticket: ticket)
        return Harness(manager: manager, activity: activity)
    }

    private func tryProgress() throws -> Harness {
        let activity = InMemoryLiveActivityManager()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(liveActivityManager: activity)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)
        return Harness(manager: manager, activity: activity)
    }

    private func gap(reserve title: String?) throws -> Harness {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let activity = InMemoryLiveActivityManager()
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            now: start,
            liveActivityManager: activity
        )
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "今")
        try manager.board(ticket: ticket)
        if let title {
            let next = try SessionManagerFixtures.makeTicket(context, title: title)
            try manager.reserveNextRide(ticket: next, via: .riding)
        }
        let rideID = try #require(manager.activeSession?.id)
        try manager.arrive()
        clock.advance(by: 5)
        try manager.recordArrivalStamp(sessionID: rideID, action: title == nil ? nil : .nextRide)
        manager.iphoneHubVisible = true
        clock.advance(by: 3 * 60)
        manager.reconcile()
        return Harness(manager: manager, activity: activity)
    }

    private func perform(_ manager: SessionManager, _ body: () async throws -> Void) async throws {
        let id = UUID()
        RideControlRuntime.testing[id] = manager
        defer { RideControlRuntime.testing[id] = nil }
        try await RideControlCall.$testingID.withValue(id, operation: body)
    }

    private func ledger(_ manager: SessionManager, _ activity: InMemoryLiveActivityManager) throws -> Ledger {
        let sessions = try manager.modelContext.fetch(FetchDescriptor<WorkSession>())
        let rows = sessions.map { session in
            let answers = session.checkInAnswers.map {
                AnswerRow(
                    kind: $0.kind.rawValue,
                    answer: $0.answer.rawValue,
                    answeredOn: $0.answeredOn,
                    answeredStage: $0.answeredStage
                )
            }.sorted { lhs, rhs in
                if lhs.answer != rhs.answer { return lhs.answer < rhs.answer }
                return (lhs.answeredStage ?? "") < (rhs.answeredStage ?? "")
            }
            let pauses = session.pauses.map {
                PauseRow(
                    ended: $0.endedAt != nil,
                    heldBy: $0.heldByRaw,
                    pausedOn: $0.pausedOnRaw
                )
            }.sorted { lhs, rhs in
                if lhs.heldBy != rhs.heldBy { return (lhs.heldBy ?? "") < (rhs.heldBy ?? "") }
                return (lhs.pausedOn ?? "") < (rhs.pausedOn ?? "")
            }
            return Row(
                title: session.ticket?.title ?? "",
                open: session.ticket?.isOpen ?? false,
                outcome: session.outcomeRaw,
                ended: session.endedAt != nil,
                pauses: pauses,
                answers: answers
            )
        }.sorted { lhs, rhs in
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.outcome ?? "" < (rhs.outcome ?? "")
        }
        return Ledger(
            phase: manager.phase,
            rows: rows,
            activityEndCount: activity.endCount,
            activityCurrent: activity.current != nil
        )
    }
}
