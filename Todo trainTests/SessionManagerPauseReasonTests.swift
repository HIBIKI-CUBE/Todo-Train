//
//  SessionManagerPauseReasonTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerPauseReasonTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func fivePathsRecordHeldByAndPausedOn() throws {
        try expectOpenPause(heldBy: .user, pausedOn: .iphone, inferred: false) { manager, context, _, _ in
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            try manager.pause()
        }
        try expectOpenPause(heldBy: .timetable, pausedOn: .iphone, inferred: false) { manager, context, _, _ in
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            try manager.pause(timetableHeld: true)
            #expect(manager.activeSession?.timetableHeld == true)
        }
        try expectOpenPause(heldBy: .alarm, pausedOn: .iphone, inferred: false) { manager, context, _, _ in
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            try manager.pauseFromAlarmKit()
        }
        try expectOpenPause(heldBy: .rideSwitch, pausedOn: .iphone, inferred: false, sessionOf: .parked) { manager, context, _, _ in
            let current = try SessionManagerFixtures.makeTicket(context, title: "いま", seconds: 600)
            let next = try SessionManagerFixtures.makeTicket(context, title: "次", seconds: 300)
            try manager.board(ticket: current)
            try manager.switchBoard(ticket: next)
        }
        try expectOpenPause(heldBy: .passenger, pausedOn: .iphone, inferred: false) { manager, context, _, _ in
            _ = insertBlock(context)
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
            try manager.board(ticket: ticket)
            manager.boardPassenger()
            #expect(manager.activeSession?.timetableHeld == true)
        }
    }

    @Test func cabinAndLiveActivityPausesAreUser() throws {
        try expectOpenPause(heldBy: .user, pausedOn: .iphone, inferred: false) { manager, context, _, _ in
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            manager.activeSession?.pendingCheckIn = .progress
            try manager.answerCheckIn(.paused)
        }
        try expectOpenPause(heldBy: .user, pausedOn: .iphone, inferred: false) { manager, context, _, _ in
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            let id = try #require(manager.activeSession?.id)
            manager.pauseRide(sessionID: id)
        }
        try expectOpenPause(heldBy: .user, pausedOn: .iphone, inferred: false) { manager, context, _, _ in
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
            try manager.board(ticket: ticket)
            try manager.pauseFromLiveActivity()
        }
    }

    @Test func atsProtectionPauseRecordsTimetable() throws {
        try expectOpenPause(heldBy: .timetable, pausedOn: .iphone, inferred: false) { manager, context, clock, _ in
            _ = insertBlock(context)
            let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
            try manager.board(ticket: ticket)
            clock.advance(by: 61)
            manager.reconcile()
            #expect(manager.activeSession?.timetableHeld == true)
        }
    }

    @Test func companionTimetableIsStoredAndOtherValuesAreRejected() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let sessionID = try #require(manager.activeSession?.id)
        try manager.applyCompanionPause(pause(sessionID: sessionID, heldBy: .timetable, at: start))
        let recorded = try openPause(manager.activeSession)
        #expect(recorded.heldBy == .timetable)
        #expect(recorded.pausedOn == .mac)
        #expect(recorded.heldByInferred == false)
        #expect(manager.activeSession?.timetableHeld == true)

        let (rejected, rejectedContext, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try rejected.startService()
        let riding = try SessionManagerFixtures.makeTicket(rejectedContext, seconds: 600)
        try rejected.board(ticket: riding)
        let rejectedID = try #require(rejected.activeSession?.id)
        #expect(throws: CompanionPauseRejection.invalidPayload) {
            try rejected.applyCompanionPause(pause(sessionID: rejectedID, heldBy: .alarm, at: start))
        }
        #expect(rejected.phase == .running)
        #expect(rejected.activeSession?.pauses.isEmpty == true)
    }

    @Test func missingHeldByUsesArrivalNotCommandAt() throws {
        try expectInferred(delta: 0, commandAtDelta: -10_000, heldBy: .timetable, timetableHeld: true)
        try expectInferred(delta: -60, commandAtDelta: 10_000, heldBy: .timetable, timetableHeld: true)
        try expectInferred(delta: 60, commandAtDelta: 0, heldBy: .timetable, timetableHeld: true)
        try expectInferred(delta: 61, commandAtDelta: 0, heldBy: .user, timetableHeld: false)
        try expectInferred(delta: -61, commandAtDelta: 0, heldBy: .user, timetableHeld: false)
    }

    @Test func explicitUserNearTheBoundaryStaysUser() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let session = try #require(manager.activeSession)
        insertGuard(context, sessionID: session.id, boundary: clock.now)
        try manager.applyCompanionPause(pause(sessionID: session.id, heldBy: .user, at: clock.now))
        let recorded = try openPause(session)
        #expect(recorded.heldBy == .user)
        #expect(recorded.heldByInferred == false)
        #expect(recorded.pausedOn == .mac)
        #expect(session.timetableHeld == false)
    }

    @Test func anotherRidesBoundaryDoesNotInferTimetable() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        let session = try #require(manager.activeSession)
        insertGuard(context, sessionID: UUID(), boundary: clock.now)
        try manager.applyCompanionPause(pause(sessionID: session.id, heldBy: nil, at: clock.now))
        let recorded = try openPause(session)
        #expect(recorded.heldBy == .user)
        #expect(recorded.heldByInferred == true)
        #expect(session.timetableHeld == false)
    }

    private enum PauseSession {
        case active
        case parked
    }

    private func expectOpenPause(
        heldBy: PauseHeldBy,
        pausedOn: PauseOrigin,
        inferred: Bool,
        sessionOf: PauseSession = .active,
        body: (SessionManager, ModelContext, FixedSessionClock, InMemoryAlarmScheduler) throws -> Void
    ) throws {
        let (manager, context, clock, scheduler) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        try body(manager, context, clock, scheduler)
        let session: WorkSession?
        switch sessionOf {
        case .active:
            session = manager.activeSession
        case .parked:
            session = manager.pausedSessions.first
        }
        let recorded = try openPause(session)
        #expect(recorded.heldBy == heldBy)
        #expect(recorded.pausedOn == pausedOn)
        #expect(recorded.heldByInferred == inferred)
    }

    private func expectInferred(
        delta: TimeInterval,
        commandAtDelta: TimeInterval,
        heldBy: PauseHeldBy,
        timetableHeld: Bool
    ) throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 1800)
        try manager.board(ticket: ticket)
        let session = try #require(manager.activeSession)
        let boundary = clock.now.addingTimeInterval(120)
        insertGuard(context, sessionID: session.id, boundary: boundary)
        clock.advance(by: 120 + delta)
        try manager.applyCompanionPause(
            pause(sessionID: session.id, heldBy: nil, at: boundary.addingTimeInterval(commandAtDelta))
        )
        let recorded = try openPause(manager.activeSession)
        #expect(recorded.heldBy == heldBy)
        #expect(recorded.pausedOn == .mac)
        #expect(recorded.heldByInferred == true)
        #expect(manager.activeSession?.timetableHeld == timetableHeld)
    }

    private func openPause(_ session: WorkSession?) throws -> SessionPause {
        let session = try #require(session)
        return try #require(session.pauses.first { $0.endedAt == nil })
    }

    private func pause(sessionID: UUID, heldBy: PauseHeldBy?, at: Date) -> CommandPlaintext {
        CommandPlaintext(
            id: UUID(),
            op: .pause,
            sessionId: sessionID,
            at: Int(at.timeIntervalSince1970),
            heldBy: heldBy
        )
    }

    private func insertBlock(_ context: ModelContext) -> TimetableBlock {
        let block = TimetableBlock(
            title: "週次",
            startsAt: start,
            endsAt: start.addingTimeInterval(3600),
            source: .manual
        )
        context.insert(block)
        try? context.save()
        return block
    }

    private func insertGuard(_ context: ModelContext, sessionID: UUID, boundary: Date) {
        context.insert(
            TimetableGuard(
                sessionID: sessionID,
                blockID: UUID(),
                notifiedAt: boundary.addingTimeInterval(-60),
                protectionBoundary: boundary
            )
        )
        try? context.save()
    }
}
