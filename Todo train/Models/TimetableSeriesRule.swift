//
//  TimetableSeriesRule.swift
//  Todo train
//
//  カレンダー繰り返しの「今後も」載せる／外す。
//

import Foundation
import SwiftData

@Model
final class TimetableSeriesRule {
    var id: UUID = UUID()
    var recurrenceIdentifier: String = ""
    var title: String = ""
    var adopted: Bool = false
    /// Occurrence start Unix seconds excluded from an adopted series ("今回だけ外す").
    var excludedOccurrenceStarts: [Double] = []

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
        self.excludedOccurrenceStarts = []
    }

    func excludes(start: Date) -> Bool {
        let key = start.timeIntervalSince1970
        return excludedOccurrenceStarts.contains { abs($0 - key) < 0.5 }
    }
}
