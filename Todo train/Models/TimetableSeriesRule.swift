//
//  TimetableSeriesRule.swift
//  Todo train
//
//  Sticky 今後も / 今後しない for a recurring calendar series.
//

import Foundation
import SwiftData

@Model
final class TimetableSeriesRule {
    var id: UUID = UUID()
    var recurrenceIdentifier: String = ""
    var title: String = ""
    var adopted: Bool = true
    var createdAt: Date = Date.now
    /// Occurrence start keys excluded from an adopted series ("今回だけ外す").
    var excludedOccurrenceStarts: [Date] = []

    init(
        id: UUID = UUID(),
        recurrenceIdentifier: String,
        title: String,
        adopted: Bool
    ) {
        self.id = id
        self.recurrenceIdentifier = recurrenceIdentifier
        self.title = title
        self.adopted = adopted
        self.createdAt = Date.now
        self.excludedOccurrenceStarts = []
    }
}
