//
//  IssueTicketIntentTests.swift
//  Todo trainTests
//

import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct IssueTicketIntentTests {
    @Test func minuteOptions_matchGaugeStops() async throws {
        let options = try await IssueEstimateMinuteOptions().results()
        #expect(options.items == EstimateSnapMapping.stops)
    }

    @Test func perform_issuesTheMinutesThatWereGiven() async throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try install(manager)
        defer { clearRuntime() }

        var intent = IssueTicketIntent()
        intent.title = "  週報  "
        intent.minutes = 15
        _ = try await intent.perform()

        let tickets = try context.fetch(FetchDescriptor<Ticket>())
        let issued = try #require(tickets.first { $0.title == "週報" })
        #expect(issued.estimatedSeconds == 15 * 60)
        #expect(manager.settings.lastIssuedEstimateMinutes == 15)
    }

    @Test func perform_emptyTitleDoesNotIssue() async throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try install(manager)
        defer { clearRuntime() }

        var intent = IssueTicketIntent()
        intent.title = "   "
        intent.minutes = nil
        _ = try await intent.perform()

        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)
    }

    @Test func perform_withoutMinutesDoesNotIssueFromHistory() async throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        manager.settings.lastIssuedEstimateMinutes = 45
        try install(manager)
        defer { clearRuntime() }

        var intent = IssueTicketIntent()
        intent.title = "週報"
        intent.minutes = nil
        await #expect(throws: (any Error).self) {
            try await intent.perform()
        }
        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)
        #expect(manager.settings.lastIssuedEstimateMinutes == 45)
    }

    private func install(_ manager: SessionManager) throws {
        AppRuntime.sessionManager = manager
        AppRuntime.modelContainer = manager.modelContext.container
    }

    private func clearRuntime() {
        AppRuntime.sessionManager = nil
        AppRuntime.modelContainer = nil
    }
}
