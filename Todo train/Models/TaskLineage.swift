//
//  TaskLineage.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class TaskLineage {
    @Attribute(.unique) var id: UUID
    /// Raw value of `LineageKind`
    var kindRaw: String
    var createdAt: Date
    var fromSessionID: UUID?
    var aiGenerated: Bool

    var parent: Ticket?
    var child: Ticket?

    var kind: LineageKind {
        get { LineageKind(rawValue: kindRaw) ?? .manual }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: LineageKind,
        parent: Ticket?,
        child: Ticket?,
        createdAt: Date = .now,
        fromSessionID: UUID? = nil,
        aiGenerated: Bool = false
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.fromSessionID = fromSessionID
        self.aiGenerated = aiGenerated
        self.parent = parent
        self.child = child
    }
}
