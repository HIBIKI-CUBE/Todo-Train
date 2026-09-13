//
//  HubPreviewSeedTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct HubPreviewSeedTests {
    @Test func empty_hasNoTicketsAndNoService() throws {
        let (container, manager) = HubPreviewSeed.make(scenario: .empty)
        let tickets = try container.mainContext.fetch(FetchDescriptor<Ticket>())
        #expect(tickets.isEmpty)
        #expect(!manager.isInService)
        #expect(manager.pausedSessions.isEmpty)
    }

    @Test func inService_seedsOpenTicketsAndStartsService() throws {
        let (container, manager) = HubPreviewSeed.make(scenario: .inService)
        let tickets = try container.mainContext.fetch(FetchDescriptor<Ticket>())
        #expect(tickets.filter(\.isOpen).count == 6)
        #expect(manager.isInService)
        #expect(manager.pausedSessions.isEmpty)
        #expect(tickets.contains { $0.title == "週次レビューの下書き" && !$0.tags.isEmpty })
        #expect(tickets.contains { $0.title == "買い物" && $0.dueDate != nil })
    }

    @Test func inServiceWithPause_parksWeeklyReview() throws {
        let (container, manager) = HubPreviewSeed.make(scenario: .inServiceWithPause)
        #expect(manager.isInService)
        #expect(manager.pausedSessions.count == 1)
        let pausedTitle = manager.pausedSessions.first?.ticket?.title
        #expect(pausedTitle == "週次レビューの下書き")
        #expect(manager.phase == .paused)
        _ = container
    }

    @Test func backlogIdle_keepsTicketsWithoutService() throws {
        let (container, manager) = HubPreviewSeed.make(scenario: .backlogIdle)
        let tickets = try container.mainContext.fetch(FetchDescriptor<Ticket>())
        #expect(tickets.count == 6)
        #expect(!manager.isInService)
    }
}
