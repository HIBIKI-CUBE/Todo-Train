//
//  FocusPendingActionTests.swift
//  Todo trainTests
//
//  P1-9: peek → match → mutate → consume. Mismatch must leave the queue.
//

import Foundation
import Testing
@testable import Todo_train

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
}
