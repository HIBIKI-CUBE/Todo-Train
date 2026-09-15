//
//  TimetableAdoptionTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TimetableAdoptionTests {
    @Test func seriesRule_insertsMissingOccurrence() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let occurrence = CalendarOccurrence(
            eventIdentifier: "evt-1",
            recurrenceIdentifier: "series-1",
            title: "スタンドアップ",
            startsAt: start,
            endsAt: start.addingTimeInterval(1800),
            isAllDay: false,
            isDeclined: false
        )
        let decisions = TimetableAdoption.materialize(
            occurrences: [occurrence],
            rules: [
                TimetableAdoption.Rule(
                    recurrenceIdentifier: "series-1",
                    adopted: true,
                    excludedOccurrenceStarts: []
                )
            ],
            existing: []
        )
        #expect(decisions == [.insert(occurrence: occurrence, scope: .series)])
    }

    @Test func excludedOccurrence_isNotInserted() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let occurrence = CalendarOccurrence(
            eventIdentifier: "evt-1",
            recurrenceIdentifier: "series-1",
            title: "スタンドアップ",
            startsAt: start,
            endsAt: start.addingTimeInterval(1800),
            isAllDay: false,
            isDeclined: false
        )
        let decisions = TimetableAdoption.materialize(
            occurrences: [occurrence],
            rules: [
                TimetableAdoption.Rule(
                    recurrenceIdentifier: "series-1",
                    adopted: true,
                    excludedOccurrenceStarts: [start]
                )
            ],
            existing: []
        )
        #expect(decisions.isEmpty)
    }

    @Test func vanishedCalendarEvent_cancelsExistingCalendarBlock() {
        let blockID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let decisions = TimetableAdoption.materialize(
            occurrences: [],
            rules: [],
            existing: [
                TimetableAdoption.ExistingBlock(
                    id: blockID,
                    calendarEventIdentifier: "evt-gone",
                    calendarRecurrenceIdentifier: nil,
                    occurrenceStartKey: Date(timeIntervalSince1970: 1_800_014_000),
                    source: .calendar,
                    isCancelled: false
                )
            ]
        )
        #expect(decisions == [.cancel(blockID: blockID)])
    }

    @Test func manualBlock_isNotCancelledWhenCalendarEmpty() {
        let blockID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let decisions = TimetableAdoption.materialize(
            occurrences: [],
            rules: [],
            existing: [
                TimetableAdoption.ExistingBlock(
                    id: blockID,
                    calendarEventIdentifier: nil,
                    calendarRecurrenceIdentifier: nil,
                    occurrenceStartKey: nil,
                    source: .manual,
                    isCancelled: false
                )
            ]
        )
        #expect(decisions.isEmpty)
    }

    @Test func allDayAndDeclined_areNotAdoptable() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let allDay = CalendarOccurrence(
            eventIdentifier: "all",
            recurrenceIdentifier: nil,
            title: "出張",
            startsAt: start,
            endsAt: start.addingTimeInterval(86_400),
            isAllDay: true,
            isDeclined: false
        )
        let declined = CalendarOccurrence(
            eventIdentifier: "no",
            recurrenceIdentifier: nil,
            title: "任意",
            startsAt: start,
            endsAt: start.addingTimeInterval(1800),
            isAllDay: false,
            isDeclined: true
        )
        #expect(!allDay.isAdoptable)
        #expect(!declined.isAdoptable)
        #expect(TimetableAdoption.materialize(occurrences: [allDay, declined], rules: [], existing: []).isEmpty)
    }
}
