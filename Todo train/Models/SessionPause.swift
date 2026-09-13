//
//  SessionPause.swift
//  Todo train
//

import Foundation
import SwiftData

/// One 停車 interval. `endedAt` is nil while the ride is still paused.
@Model
final class SessionPause {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date?
    var session: WorkSession?

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        session: WorkSession? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.session = session
    }
}
