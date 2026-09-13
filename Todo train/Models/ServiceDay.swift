//
//  ServiceDay.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class ServiceDay {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date?
    /// Calendar day key, e.g. "2026-08-11" in the user's current calendar/timezone.
    var calendarDayKey: String = ""
    var pendingCabinKindRaw: String?
    var cabinIdleFiredCount: Int = 0
    var lastCabinActivityAt: Date?

    var isOpen: Bool { endedAt == nil }

    var pendingCabin: CheckInKind? {
        get { pendingCabinKindRaw.flatMap(CheckInKind.init(rawValue:)) }
        set { pendingCabinKindRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        calendarDayKey: String
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.calendarDayKey = calendarDayKey
        self.lastCabinActivityAt = startedAt
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
