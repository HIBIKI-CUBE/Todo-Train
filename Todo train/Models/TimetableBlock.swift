//
//  TimetableBlock.swift
//  Todo train
//
//  ダイヤ: 運行から外した占有。乗る対象ではない。
//

import Foundation
import SwiftData

nonisolated enum TimetableSource: String, Codable, Sendable, Equatable {
    case manual
    case calendar
}

nonisolated enum TimetableAdoptionScope: String, Codable, Sendable, Equatable {
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
    /// Stable occurrence identity (Unix seconds of the occurrence start).
    var occurrenceStartKey: Double?
    var createdAt: Date = Date.now

    var source: TimetableSource {
        get { TimetableSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var adoptionScope: TimetableAdoptionScope {
        get { TimetableAdoptionScope(rawValue: adoptionScopeRaw) ?? .occurrence }
        set { adoptionScopeRaw = newValue.rawValue }
    }

    var isActive: Bool { !isCancelled && endsAt > startsAt }

    init(
        id: UUID = UUID(),
        title: String,
        startsAt: Date,
        endsAt: Date,
        source: TimetableSource,
        adoptionScope: TimetableAdoptionScope = .occurrence,
        calendarEventIdentifier: String? = nil,
        calendarRecurrenceIdentifier: String? = nil,
        occurrenceStartKey: Double? = nil,
        createdAt: Date = Date.now
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
        self.occurrenceStartKey = occurrenceStartKey ?? startsAt.timeIntervalSince1970
        self.createdAt = createdAt
    }
}
