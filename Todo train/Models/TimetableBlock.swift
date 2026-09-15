//
//  TimetableBlock.swift
//  Todo train
//
//  A wall-clock occupancy the user put on today's ダイヤ. Not a Ticket.
//

import Foundation
import SwiftData

enum TimetableSource: String, Codable, Sendable {
    case manual
    case calendar
}

enum TimetableAdoptionScope: String, Codable, Sendable {
    case occurrence
    case series
}

@Model
final class TimetableBlock {
    var id: UUID = UUID()
    var title: String = ""
    var startsAt: Date = Date.now
    var endsAt: Date = Date.now
    var sourceRaw: String = TimetableSource.manual.rawValue
    var adoptionScopeRaw: String = TimetableAdoptionScope.occurrence.rawValue
    var isCancelled: Bool = false
    var needsReview: Bool = false
    var calendarEventIdentifier: String?
    var calendarRecurrenceIdentifier: String?
    var occurrenceStartKey: Date?
    var createdAt: Date = Date.now

    var source: TimetableSource {
        get { TimetableSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var adoptionScope: TimetableAdoptionScope {
        get { TimetableAdoptionScope(rawValue: adoptionScopeRaw) ?? .occurrence }
        set { adoptionScopeRaw = newValue.rawValue }
    }

    var isActive: Bool { !isCancelled }

    init(
        id: UUID = UUID(),
        title: String,
        startsAt: Date,
        endsAt: Date,
        source: TimetableSource,
        adoptionScope: TimetableAdoptionScope = .occurrence,
        calendarEventIdentifier: String? = nil,
        calendarRecurrenceIdentifier: String? = nil,
        occurrenceStartKey: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.sourceRaw = source.rawValue
        self.adoptionScopeRaw = adoptionScope.rawValue
        self.isCancelled = false
        self.needsReview = false
        self.calendarEventIdentifier = calendarEventIdentifier
        self.calendarRecurrenceIdentifier = calendarRecurrenceIdentifier
        self.occurrenceStartKey = occurrenceStartKey
        self.createdAt = Date.now
    }
}
