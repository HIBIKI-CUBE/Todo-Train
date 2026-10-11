//
//  Ticket.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class Ticket {
    var id: UUID = UUID()
    var title: String = ""
    var estimatedSeconds: Int = 0
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var dueDate: Date?
    var closedAt: Date?
    /// Raw value of `ClosureKind`
    var closureKindRaw: String?
    /// 次の一本として予約した時刻。予約は乗車を始めない。未予約は nil。
    var reservedAt: Date?
    /// 予約したときに乗っていた乗車。
    var reservedFromRideId: UUID?
    /// Raw value of `ReservationVia`.
    var reservedViaRaw: String?

    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkSession.ticket)
    var sessions: [WorkSession] = []

    @Relationship(deleteRule: .nullify, inverse: \TaskLineage.parent)
    var childLineages: [TaskLineage] = []

    @Relationship(deleteRule: .nullify, inverse: \TaskLineage.child)
    var parentLineages: [TaskLineage] = []

    var closureKind: ClosureKind? {
        get { closureKindRaw.flatMap(ClosureKind.init(rawValue:)) }
        set { closureKindRaw = newValue?.rawValue }
    }

    var reservedVia: ReservationVia? {
        get { reservedViaRaw.flatMap(ReservationVia.init(rawValue:)) }
        set { reservedViaRaw = newValue?.rawValue }
    }

    var isReservedAsNextRide: Bool { reservedAt != nil }

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
        self.reservedAt = nil
        self.reservedFromRideId = nil
        self.reservedViaRaw = nil
        self.tags = []
        self.sessions = []
        self.childLineages = []
        self.parentLineages = []
    }

    static let maxEstimatedSeconds = 3600
}
