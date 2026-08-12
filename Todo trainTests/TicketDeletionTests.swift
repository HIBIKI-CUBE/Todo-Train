//
//  TicketDeletionTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TicketDeletionTests {
    @Test func canDeleteEndedSession_requiresEndedAt() {
        let open = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600)
        #expect(!TicketDeletion.canDeleteEndedSession(open))

        open.endedAt = .now
        #expect(TicketDeletion.canDeleteEndedSession(open))
    }

    @Test func shouldDeleteOrphanTicket_whenLastSessionRemoved() {
        let a = UUID()
        let b = UUID()
        #expect(
            TicketDeletion.shouldDeleteOrphanTicket(remainingSessionIDs: [a], removing: a)
        )
        #expect(
            !TicketDeletion.shouldDeleteOrphanTicket(remainingSessionIDs: [a, b], removing: a)
        )
        #expect(
            TicketDeletion.shouldDeleteOrphanTicket(remainingSessionIDs: [], removing: a)
        )
    }

    @Test func displayTitle_trimsAndFallsBack() {
        #expect(TicketDeletion.displayTitle("  報告書  ", fallback: "無題の切符") == "報告書")
        #expect(TicketDeletion.displayTitle("   ", fallback: "無題の切符") == "無題の切符")
    }

    @Test func rideState_priorityIsRunningThenPausedThenHistory() {
        #expect(
            TicketDeletion.rideState(hasEndedSessions: false, isPaused: false, isRunning: false) == .unused
        )
        #expect(
            TicketDeletion.rideState(hasEndedSessions: true, isPaused: false, isRunning: false) == .idle
        )
        #expect(
            TicketDeletion.rideState(hasEndedSessions: true, isPaused: true, isRunning: false) == .paused
        )
        #expect(
            TicketDeletion.rideState(hasEndedSessions: true, isPaused: true, isRunning: true) == .running
        )
    }

    @Test func sectionFooters_mentionUndoWindow() {
        #expect(TicketDeletion.ticketDeleteFooter(ride: .unused).contains("取り消せます"))
        #expect(TicketDeletion.ticketDeleteFooter(ride: .idle).contains("乗車記録"))
        #expect(TicketDeletion.ticketDeleteFooter(ride: .paused).contains("停車中"))
        #expect(TicketDeletion.ticketDeleteFooter(ride: .running).contains("フォーカス"))
        #expect(TicketDeletion.tagDeleteFooter(ticketCount: 0).contains("取り消せます"))
        #expect(TicketDeletion.tagDeleteFooter(ticketCount: 2).contains("2 枚"))
    }
}
