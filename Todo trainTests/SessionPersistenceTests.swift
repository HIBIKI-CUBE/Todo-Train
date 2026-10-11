//
//  SessionPersistenceTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionPersistenceTests {
    @Test func saveBestEffort_returnsTrueAfterMutation() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)

        #expect(manager.saveBestEffort())
        #expect(manager.activeSession?.ticket?.id == ticket.id)
    }

    @Test func restoreDeletedTicket_throwsAreNotSwallowedByAPI() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "戻す", seconds: 600)
        let record = DeletionUndo.captureTicket(ticket)
        try manager.deleteTicket(ticket)

        try manager.restoreDeletedTicket(record)
        let restored = try context.fetch(FetchDescriptor<Ticket>()).first { $0.id == record.id }
        #expect(restored?.title == "戻す")
    }
}
