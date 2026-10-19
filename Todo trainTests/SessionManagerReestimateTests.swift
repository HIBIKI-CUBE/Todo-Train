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
