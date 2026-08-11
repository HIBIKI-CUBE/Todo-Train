//
//  Tag.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
    var createdAt: Date

    @Relationship(inverse: \Ticket.tags)
    var tickets: [Ticket]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#888888",
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.tickets = []
    }
}
