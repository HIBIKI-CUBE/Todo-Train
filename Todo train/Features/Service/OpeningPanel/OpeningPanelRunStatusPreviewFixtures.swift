//
//  OpeningPanelRunStatusPreviewFixtures.swift
//  Todo train
//
#if DEBUG

import Foundation

enum OpeningPanelRunStatusPreviewFixtures {
    static let dayStart = Date(timeIntervalSince1970: 1_699_920_000)

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func at(hour: Int, minute: Int = 0) -> Date {
        utc.date(byAdding: .minute, value: hour * 60 + minute, to: dayStart)!
    }

    static let stdScheduled: [TimetableOpeningInterval] = [
        interval(startHour: 9, startMinute: 30, endHour: 9, endMinute: 45),
        interval(startHour: 10, startMinute: 0, endHour: 11, endMinute: 0),
        interval(startHour: 13, startMinute: 0, endHour: 13, endMinute: 30),
        interval(startHour: 16, startMinute: 30, endHour: 18, endMinute: 30),
    ]

    static let stdAdopted: [TimetableOpeningInterval] = [
        interval(startHour: 9, startMinute: 30, endHour: 9, endMinute: 45),
        interval(startHour: 10, startMinute: 0, endHour: 11, endMinute: 0),
        interval(startHour: 16, startMinute: 30, endHour: 18, endMinute: 30),
    ]

    static let packedScheduled: [TimetableOpeningInterval] = [
        interval(startHour: 8, startMinute: 0, endHour: 8, endMinute: 15),
        interval(startHour: 8, startMinute: 15, endHour: 8, endMinute: 30),
        interval(startHour: 8, startMinute: 45, endHour: 9, endMinute: 0),
        interval(startHour: 9, startMinute: 0, endHour: 10, endMinute: 0),
        interval(startHour: 10, startMinute: 0, endHour: 10, endMinute: 20),
        interval(startHour: 10, startMinute: 30, endHour: 11, endMinute: 30),
    ]

    static let packedAdopted: [TimetableOpeningInterval] = [
        interval(startHour: 8, startMinute: 0, endHour: 8, endMinute: 15),
        interval(startHour: 8, startMinute: 15, endHour: 8, endMinute: 30),
        interval(startHour: 9, startMinute: 0, endHour: 10, endMinute: 0),
        interval(startHour: 10, startMinute: 0, endHour: 10, endMinute: 20),
    ]

    private static func interval(
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int
    ) -> TimetableOpeningInterval {
        TimetableOpeningInterval(
            startsAt: at(hour: startHour, minute: startMinute),
            endsAt: at(hour: endHour, minute: endMinute)
        )
    }

    static var stdRange: TimetableRange {
        TimetableRangeLogic.compute(
            scheduledBlocks: stdScheduled,
            referenceDay: dayStart,
            calendar: utc
        )
    }

    static var stdBands: [RunStatusBand] {
        RunStatusLogic.bands(range: stdRange, adoptedBlocks: stdAdopted)
    }

    static var packedRange: TimetableRange {
        TimetableRangeLogic.compute(
            scheduledBlocks: packedScheduled,
            referenceDay: dayStart,
            calendar: utc
        )
    }

    static var packedBands: [RunStatusBand] {
        RunStatusLogic.bands(range: packedRange, adoptedBlocks: packedAdopted)
    }

    static func reading(hour: Int, minute: Int = 0, packed: Bool = false) -> RunStatusNow {
        let range = packed ? packedRange : stdRange
        let bands = packed ? packedBands : stdBands
        return RunStatusLogic.nowReading(
            now: at(hour: hour, minute: minute),
            range: range,
            bands: bands
        )
    }
}

#endif