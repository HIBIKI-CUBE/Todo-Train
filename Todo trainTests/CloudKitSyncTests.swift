//
//  CloudKitSyncTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct CloudKitSyncTests {
    @Test func isConfigured_defaultsOff() {
        CloudKitSync.isConfiguredOverride = nil
        #expect(!CloudKitSync.isConfigured)
    }

    @Test func inMemoryContainer_usesLocalStore() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let ticket = Ticket(title: "同期前", estimatedSeconds: 600)
        container.mainContext.insert(ticket)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<Ticket>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "同期前")
    }
}
