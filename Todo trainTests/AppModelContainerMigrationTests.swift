//
//  AppModelContainerMigrationTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct AppModelContainerMigrationTests {
    @Test func inMemory_canInsertTimetableModels() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let starts = Date(timeIntervalSince1970: 1_700_000_000)
        let block = TimetableBlock(
            title: "1on1",
            startsAt: starts,
            endsAt: starts.addingTimeInterval(1800),
            source: .manual
        )
        container.mainContext.insert(block)
        container.mainContext.insert(
            TimetableGuard(
                sessionID: UUID(),
                blockID: block.id,
                notifiedAt: starts,
                protectionBoundary: starts.addingTimeInterval(120)
            )
        )
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<TimetableBlock>()).count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<TimetableGuard>()).count == 1)
    }

    @Test func make_migratesUnversionedStoreWithoutLosingTickets() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "todo-train-schema-\(UUID().uuidString).store")
        defer { Self.removeStoreFiles(at: url) }

        try autoreleasepool {
            let v1Schema = Schema(versionedSchema: AppSchemaV1.self)
            let v1Container = try ModelContainer(
                for: v1Schema,
                configurations: [ModelConfiguration(schema: v1Schema, url: url)]
            )
            let ticket = Ticket(title: "残す切符", estimatedSeconds: 900, sortOrder: 3)
            v1Container.mainContext.insert(ticket)
            let session = WorkSession(
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                estimatedSecondsAtStart: 900,
                ticket: ticket
            )
            session.endedAt = Date(timeIntervalSince1970: 1_700_000_600)
            v1Container.mainContext.insert(session)
            try v1Container.mainContext.save()
        }

        let migrated = try AppModelContainer.make(storeURL: url)
        let tickets = try migrated.mainContext.fetch(FetchDescriptor<Ticket>())
        let sessions = try migrated.mainContext.fetch(FetchDescriptor<WorkSession>())
        #expect(tickets.map(\.title) == ["残す切符"])
        #expect(tickets.first?.estimatedSeconds == 900)
        #expect(sessions.count == 1)
        #expect(sessions.first?.ticket?.title == "残す切符")

        let starts = Date(timeIntervalSince1970: 1_700_001_000)
        migrated.mainContext.insert(
            TimetableBlock(
                title: "レビュー",
                startsAt: starts,
                endsAt: starts.addingTimeInterval(3600),
                source: .calendar
            )
        )
        try migrated.mainContext.save()
        #expect(try migrated.mainContext.fetch(FetchDescriptor<TimetableBlock>()).count == 1)
    }

    private static func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        for extra in [url, URL(fileURLWithPath: url.path + "-shm"), URL(fileURLWithPath: url.path + "-wal")] {
            try? fileManager.removeItem(at: extra)
        }
    }
}
