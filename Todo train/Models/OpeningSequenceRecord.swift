//
//  OpeningSequenceRecord.swift
//  Todo train
//
//  SEQ の記録。利用者には出さない。題名は入れない。
//

import Foundation
import SwiftData

@Model
final class OpeningSequenceRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var dayStart: Date = Date.now
    var freeMinutes: Double = 0
    var lineIndex: Int = 0
    var placementsJSON: String = ""
    var answersJSON: String = ""

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        dayStart: Date,
        freeMinutes: Double,
        lineIndex: Int,
        placementsJSON: String,
        answersJSON: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.dayStart = dayStart
        self.freeMinutes = freeMinutes
        self.lineIndex = lineIndex
        self.placementsJSON = placementsJSON
        self.answersJSON = answersJSON
    }
}

@Model
final class OpeningSequenceBelowDays {
    var ticketID: UUID = UUID()
    var consecutiveDays: Int = 0
    var lastBelowDay: Date?

    init(ticketID: UUID, consecutiveDays: Int, lastBelowDay: Date?) {
        self.ticketID = ticketID
        self.consecutiveDays = consecutiveDays
        self.lastBelowDay = lastBelowDay
    }
}
