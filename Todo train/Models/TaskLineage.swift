//
//  TaskLineage.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class TaskLineage {
    var id: UUID = UUID()
    /// Raw value of `LineageKind`
    var kindRaw: String = "manual"
    var createdAt: Date = Date.now
    var fromSessionID: UUID?
    var aiGenerated: Bool = false

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
