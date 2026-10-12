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
    /// 停車を保っている主体。`PauseHeldBy` の raw。空は理由が残っていない古い停車。
    var heldByRaw: String?
    /// 停車した端末。
    var pausedOnRaw: String?
    var heldByInferred: Bool = false
    var macSampledSeconds: Double = 0
    var macActiveSeconds: Double = 0
    var promptedAt: Date?
    var promptAnswerRaw: String?
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
        self.heldByRaw = nil
        self.pausedOnRaw = nil
        self.heldByInferred = false
        self.macSampledSeconds = 0
        self.macActiveSeconds = 0
        self.promptedAt = nil
        self.promptAnswerRaw = nil
        self.session = session
    }
}
