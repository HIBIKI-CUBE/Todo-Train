//
//  TimetableRange.swift
//  Todo train
//
//  TIMETABLE の表示範囲。予定の端から切り上げ／切り下げし、最小 4 時間を保つ。
//

import Foundation

/// 運行開始の盤が扱う予定区間。着発・掲示の区別は呼び出し側が渡す配列で決める。
nonisolated struct TimetableOpeningInterval: Equatable, Sendable {
    var startsAt: Date
    var endsAt: Date

    init(startsAt: Date, endsAt: Date) {
        self.startsAt = startsAt
        self.endsAt = endsAt
    }
}

nonisolated struct TimetableRange: Equatable, Sendable {
    var startsAt: Date
    var endsAt: Date
    var spanHours: Int
    /// 範囲の窓（例: `09–19 10H`）。
    var windowLabel: String
}

nonisolated enum TimetableRangeLogic {
    static let emptyDayLowerHour = 6
    static let emptyDayUpperHour = 24
    static let minimumSpanHours = 4
    static let fullDayLowerHour = 0
    static let fullDayUpperHour = 24

    static func compute(
        scheduledBlocks: [TimetableOpeningInterval],
        referenceDay: Date,
        isTwentyFourHour: Bool = false,
        calendar: Calendar = .current
    ) -> TimetableRange {
        if isTwentyFourHour {
            return makeRange(
                lowerHour: fullDayLowerHour,
                upperHour: fullDayUpperHour,
                referenceDay: referenceDay,
                calendar: calendar
            )
        }

        let valid = scheduledBlocks.filter { $0.endsAt > $0.startsAt }
        guard !valid.isEmpty else {
            return makeRange(
                lowerHour: emptyDayLowerHour,
                upperHour: emptyDayUpperHour,
                referenceDay: referenceDay,
                calendar: calendar
            )
        }

        let earliest = valid.map(\.startsAt).min()!
        let latest = valid.map(\.endsAt).max()!

        var lowerHour = floorHour(earliest, referenceDay: referenceDay, calendar: calendar)
        var upperHour = ceilHour(latest, referenceDay: referenceDay, calendar: calendar)
        if upperHour - lowerHour < minimumSpanHours {
            upperHour = lowerHour + minimumSpanHours
            if upperHour > fullDayUpperHour {
                upperHour = fullDayUpperHour
                lowerHour = max(fullDayLowerHour, upperHour - minimumSpanHours)
            }
        }

        return makeRange(
            lowerHour: lowerHour,
            upperHour: upperHour,
            referenceDay: referenceDay,
            calendar: calendar
        )
    }

    static func floorHour(_ date: Date, referenceDay: Date, calendar: Calendar) -> Int {
        let dayStart = calendar.startOfDay(for: referenceDay)
        let elapsed = date.timeIntervalSince(dayStart)
        let hour = Int(floor(elapsed / 3600))
        return min(fullDayUpperHour, max(fullDayLowerHour, hour))
    }

    static func ceilHour(_ date: Date, referenceDay: Date, calendar: Calendar) -> Int {
        let dayStart = calendar.startOfDay(for: referenceDay)
        let elapsed = date.timeIntervalSince(dayStart)
        let hour = Int(ceil(elapsed / 3600))
        return min(fullDayUpperHour, max(fullDayLowerHour, hour))
    }

    private static func makeRange(
        lowerHour: Int,
        upperHour: Int,
        referenceDay: Date,
        calendar: Calendar
    ) -> TimetableRange {
        let day = calendar.startOfDay(for: referenceDay)
        let startsAt = calendar.date(byAdding: .hour, value: lowerHour, to: day)!
        let endsAt = calendar.date(byAdding: .hour, value: upperHour, to: day)!
        let spanHours = upperHour - lowerHour
        let label = String(format: "%02d–%02d %dH", lowerHour, upperHour, spanHours)
        return TimetableRange(
            startsAt: startsAt,
            endsAt: endsAt,
            spanHours: spanHours,
            windowLabel: label
        )
    }
}