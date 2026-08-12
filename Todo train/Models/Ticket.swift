//
//  Ticket.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class Ticket {
    @Attribute(.unique) var id: UUID
    var title: String
    var estimatedSeconds: Int
    var sortOrder: Int
    var createdAt: Date
    var dueDate: Date?
    var closedAt: Date?
    /// Raw value of `ClosureKind`
    var closureKindRaw: String?

    var tags: [Tag]

    @Relationship(deleteRule: .cascade, inverse: \WorkSession.ticket)
    var sessions: [WorkSession]

    @Relationship(deleteRule: .nullify, inverse: \TaskLineage.parent)
    var childLineages: [TaskLineage]

    @Relationship(deleteRule: .nullify, inverse: \TaskLineage.child)
    var parentLineages: [TaskLineage]

    var closureKind: ClosureKind? {
        get { closureKindRaw.flatMap(ClosureKind.init(rawValue:)) }
        set { closureKindRaw = newValue?.rawValue }
    }

    var isOpen: Bool { closedAt == nil }

    init(
        id: UUID = UUID(),
        title: String,
        estimatedSeconds: Int,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.estimatedSeconds = min(max(estimatedSeconds, 0), Ticket.maxEstimatedSeconds)
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.closedAt = nil
        self.closureKindRaw = nil
        self.tags = []
        self.sessions = []
        self.childLineages = []
        self.parentLineages = []
    }

    static let maxEstimatedSeconds = 3600
}
