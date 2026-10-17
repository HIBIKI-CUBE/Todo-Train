//
//  FocusPendingActionTests.swift
//  Todo trainTests
//
//  P1-9: peek → match → mutate → consume. Mismatch must leave the queue.
//

import Foundation
import Testing
@testable import Todo_train

@Suite(.serialized)
@MainActor
struct FocusPendingActionTests {
    private func withIsolatedStore(_ body: () throws -> Void) rethrows {
        let suiteName = "focus-pending-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removeObject(forKey: FocusPendingActionStore.suiteKey)
        let previous = FocusPendingActionStore.defaultsOverride
        FocusPendingActionStore.defaultsOverride = suite
        defer {
            suite.removeObject(forKey: FocusPendingActionStore.suiteKey)
            FocusPendingActionStore.defaultsOverride = previous
            suite.removePersistentDomain(forName: suiteName)
        }
        try body()
    }

    @Test func discardArriveAndExtendHandoffs_clearsQueuedArrive() throws {
        try withIsolatedStore {
            FocusPendingActionStore.enqueue(
                FocusPendingAction(kind: .arrive, sessionID: UUID(), createdAt: .now)
            )
            FocusPendingActionStore.discardArriveAndExtendHandoffs()
            #expect(FocusPendingActionStore.peek() == nil)
        }
    }

    @Test func discardArriveAndExtendHandoffs_leavesPauseQueued() throws {
        try withIsolatedStore {
            let pause = FocusPendingAction(kind: .pause, sessionID: UUID(), createdAt: .now)
            FocusPendingActionStore.enqueue(pause)
            FocusPendingActionStore.discardArriveAndExtendHandoffs()
            #expect(FocusPendingActionStore.peek() == pause)
        }
    }

    @Test func stalePause_keepsQueueAndDoesNotPause() throws {
        try withIsolatedStore {
            let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
            try manager.startService()
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            let activeID = try #require(manager.activeSession?.id)

            FocusPendingActionStore.enqueue(
                FocusPendingAction(kind: .pause, sessionID: UUID(), createdAt: .now)
            )

            let applied = manager.applyPendingLiveActivityAction()
            #expect(applied == nil)
            #expect(manager.phase == .running)
            #expect(FocusPendingActionStore.peek()?.sessionID != activeID)
            #expect(FocusPendingActionStore.peek()?.kind == .pause)
        }
    }

    @Test func matchingPause_consumesAndPauses() throws {
        try withIsolatedStore {
            let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
            try manager.startService()
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            let activeID = try #require(manager.activeSession?.id)

            FocusPendingActionStore.enqueue(
                FocusPendingAction(kind: .pause, sessionID: activeID, createdAt: .now)
            )

            let applied = manager.applyPendingLiveActivityAction()
            #expect(applied == .pause)
            #expect(manager.phase == .paused)
            #expect(FocusPendingActionStore.peek() == nil)
        }
    }

    @Test func matchingResume_consumesAndResumes() throws {
        try withIsolatedStore {
            let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
            try manager.startService()
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            try manager.pause()
            let activeID = try #require(manager.activeSession?.id)
            #expect(manager.phase == .paused)

            FocusPendingActionStore.enqueue(
                FocusPendingAction(kind: .resume, sessionID: activeID, createdAt: .now)
            )

            let applied = manager.applyPendingLiveActivityAction()
            #expect(applied == .resume)
            #expect(manager.phase == .running)
            #expect(FocusPendingActionStore.peek() == nil)
        }
    }

    @Test func stalePause_survivesRecoverOnLaunch_thenAppliesWhenSessionMatches() throws {
        try withIsolatedStore {
            let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
            try manager.startService()
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            let activeID = try #require(manager.activeSession?.id)

            // Stale handoff left from a previous ride.
            FocusPendingActionStore.enqueue(
                FocusPendingAction(kind: .pause, sessionID: UUID(), createdAt: .now)
            )
            try manager.recoverOnLaunch()
            #expect(manager.phase == .running)
            #expect(FocusPendingActionStore.peek()?.kind == .pause)

            // Correct handoff replaces the queue (single-slot store).
            FocusPendingActionStore.enqueue(
                FocusPendingAction(kind: .pause, sessionID: activeID, createdAt: .now)
            )
            let applied = manager.applyPendingLiveActivityAction()
            #expect(applied == .pause)
            #expect(manager.phase == .paused)
            #expect(FocusPendingActionStore.peek() == nil)
        }
    }

    @Test func nilActiveSession_keepsQueue() throws {
        try withIsolatedStore {
            let (manager, _, _, _) = try SessionManagerFixtures.makeHarness()
            #expect(manager.activeSession == nil)

            let orphan = UUID()
            FocusPendingActionStore.enqueue(
                FocusPendingAction(kind: .resume, sessionID: orphan, createdAt: .now)
            )

            let applied = manager.applyPendingLiveActivityAction()
            #expect(applied == nil)
            #expect(FocusPendingActionStore.peek()?.sessionID == orphan)
        }
    }

    @Test func consumeIfMatches_leavesANewerHandoff() throws {
        try withIsolatedStore {
            let first = FocusPendingAction(
                kind: .pause,
                sessionID: UUID(),
                createdAt: Date(timeIntervalSince1970: 1)
            )
            let newer = FocusPendingAction(
                kind: .arrive,
                sessionID: UUID(),
                createdAt: Date(timeIntervalSince1970: 2)
            )
            FocusPendingActionStore.enqueue(first)
            FocusPendingActionStore.enqueue(newer)

            #expect(FocusPendingActionStore.consumeIfMatches(first) == false)
            #expect(FocusPendingActionStore.peek() == newer)
            #expect(FocusPendingActionStore.consumeIfMatches(newer))
            #expect(FocusPendingActionStore.peek() == nil)
        }
    }

    @Test func overtimeArriveWhileFocusVisible_clearsBeforeALaterRunningPass() throws {
        try withIsolatedStore {
            let sessionID = UUID()
            let arrive = FocusPendingAction(kind: .arrive, sessionID: sessionID, createdAt: .now)
            FocusPendingActionStore.enqueue(arrive)

            let whileShown = ArriveHandoff.decision(
                sessionMatches: true,
                phase: .overtime,
                focusIsPresented: true
            )
            #expect(whileShown == .consumeOnly)
            if whileShown == .consumeOnly {
                FocusPendingActionStore.consumeIfMatches(arrive)
            }

            // Extend moves phase to running and Focus stays up. The queued arrive
            // must already be gone, or this decision would land the ride.
            let afterExtend = ArriveHandoff.decision(
                sessionMatches: true,
                phase: .running,
                focusIsPresented: true
            )
            #expect(afterExtend == .performArrive)
            #expect(FocusPendingActionStore.peek() == nil)
        }
    }

    @Test func overtimeArriveBeforeFocus_staysUntilFocusIsPresented() throws {
        try withIsolatedStore {
            let arrive = FocusPendingAction(kind: .arrive, sessionID: UUID(), createdAt: .now)
            FocusPendingActionStore.enqueue(arrive)

            #expect(
                ArriveHandoff.decision(
                    sessionMatches: true,
                    phase: .overtime,
                    focusIsPresented: false
                ) == .leaveQueued
            )
            #expect(FocusPendingActionStore.peek() == arrive)

            #expect(
                ArriveHandoff.decision(
                    sessionMatches: true,
                    phase: .overtime,
                    focusIsPresented: true
                ) == .consumeOnly
            )
            FocusPendingActionStore.consumeIfMatches(arrive)
            #expect(FocusPendingActionStore.peek() == nil)
        }
    }

    @Test func arriveHandoff_mismatchAndHiddenOvertimeStayQueued() {
        #expect(
            ArriveHandoff.decision(
                sessionMatches: false,
                phase: .overtime,
                focusIsPresented: true
            ) == .leaveQueued
        )
        #expect(
            ArriveHandoff.decision(
                sessionMatches: true,
                phase: .running,
                focusIsPresented: false
            ) == .performArrive
        )
        #expect(
            ArriveHandoff.shouldDropOnLeavingOvertime(
                kind: .arrive,
                sessionMatches: true,
                focusWasPresented: true
            )
        )
        #expect(
            !ArriveHandoff.shouldDropOnLeavingOvertime(
                kind: .arrive,
                sessionMatches: true,
                focusWasPresented: false
            )
        )
        #expect(
            !ArriveHandoff.shouldDropOnLeavingOvertime(
                kind: .pause,
                sessionMatches: true,
                focusWasPresented: true
            )
        )
    }
}
