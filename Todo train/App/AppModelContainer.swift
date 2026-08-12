//
//  AppModelContainer.swift
//  Todo train
//

import Foundation
import SwiftData

enum AppModelContainer {
    static let schema = Schema([
        Ticket.self,
        WorkSession.self,
        SessionExtension.self,
        Tag.self,
        TaskLineage.self,
        ServiceDay.self,
    ])

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
