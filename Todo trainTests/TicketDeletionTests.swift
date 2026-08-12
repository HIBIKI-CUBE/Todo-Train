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
}
