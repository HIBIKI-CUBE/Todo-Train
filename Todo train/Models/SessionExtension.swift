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
    /// Active seconds at `createdAt`. A later pause stays in the accumulated total, so the reading is stored here.
    var workingSeconds: Double?
    var session: WorkSession?

    init(
        id: UUID = UUID(),
        addedSeconds: Int,
        reason: String? = nil,
        createdAt: Date = .now,
        workingSeconds: Double? = nil,
        session: WorkSession? = nil
    ) {
        self.id = id
        self.addedSeconds = max(0, addedSeconds)
        self.reason = reason
        self.createdAt = createdAt
        self.workingSeconds = workingSeconds
        self.session = session
    }
}
