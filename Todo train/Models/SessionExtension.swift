//
//  SessionExtension.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class SessionExtension {
    @Attribute(.unique) var id: UUID
    var addedSeconds: Int
    var reason: String?
    var createdAt: Date
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
