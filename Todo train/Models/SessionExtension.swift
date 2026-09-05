//
//  SessionExtension.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class SessionExtension {
    var id: UUID = UUID()
    var addedSeconds: Int = 0
    var reason: String?
    var createdAt: Date = Date.now
    var session: WorkSession?

    init(
        id: UUID = UUID(),
        addedSeconds: Int,
        reason: String? = nil,
        createdAt: Date = .now,
        session: WorkSession? = nil
    ) {
        self.id = id
        self.addedSeconds = max(0, addedSeconds)
        self.reason = reason
        self.createdAt = createdAt
        self.session = session
    }
}
