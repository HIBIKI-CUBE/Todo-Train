//
//  TimetableGuard.swift
//  Todo train
//
//  ATS audit record for one ride × one ダイヤ block. Not printed in UI.
//

import Foundation
import SwiftData

@Model
final class TimetableGuard {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var blockID: UUID = UUID()
    var notifiedAt: Date = Date.now
    var protectionBoundary: Date = Date.now
    var resolvedAt: Date?
    var invalidatedAt: Date?

    var isOpen: Bool { resolvedAt == nil && invalidatedAt == nil }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        blockID: UUID,
        notifiedAt: Date,
        protectionBoundary: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.blockID = blockID
        self.notifiedAt = notifiedAt
        self.protectionBoundary = protectionBoundary
        self.resolvedAt = nil
        self.invalidatedAt = nil
    }
}
