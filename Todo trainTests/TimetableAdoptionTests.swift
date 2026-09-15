//
//  TimetableAdoptionTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

@MainActor
struct TimetableAdoptionTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func occurrence(
        id: String = "evt-1",
        recurrence: String? = nil,
        title: String = "週次",
        startOffset: TimeInterval = 0,
        duration: TimeInterval = 1800,
        allDay: Bool = false,
        declined: Bool = false
    ) -> CalendarOccurrence {
        CalendarOccurrence(
            eventIdentifier: id,
            recurrenceIdentifier: recurrence,
            title: title,
            startsAt: start.addingTimeInterval(startOffset),
            endsAt: start.addingTimeInterval(startOffset + duration),
            isAllDay: allDay,
            isDeclined: declined
        )
    }

    @Test func allDayAndDeclined_areNotEligible() {
        #expect(!TimetableAdoption.isEligible(occurrence(allDay: true)))
        #expect(!TimetableAdoption.isEligible(occurrence(declined: true)))
        #expect(TimetableAdoption.isEligible(occurrence()))
    }

    @Test func refresh_doesNotInsertUnadoptedCalendar() {
        let membership = TimetableAdoption.refreshCalendarMembership(
            occurrences: [occurrence()],
            membership: TimetableMembership(blocks: [], rules: [])
        )
        #expect(membership.blocks.isEmpty)
    }

    @Test func refresh_keepsManualWhenCalendarEmpty() {
        let manual = TimetableAdoption.adoptManual(
            title: "歯医者",
            startsAt: start,
            endsAt: start.addingTimeInterval(1800),
            membership: TimetableMembership(blocks: [], rules: [])
        )
        let refreshed = TimetableAdoption.refreshCalendarMembership(
            occurrences: [],
            membership: manual
        )
        #expect(refreshed.blocks.count == 1)
        #expect(refreshed.blocks[0].source == .manual)
        #expect(!refreshed.blocks[0].isCancelled)
    }

    @Test func adoptOccurrence_insertsThisTimeOnly() {
        let occ = occurrence(recurrence: "series-a")
        let adopted = TimetableAdoption.adoptOccurrence(
            occ,
            scope: .occurrence,
            membership: TimetableMembership(blocks: [], rules: [])
        )
        #expect(adopted.blocks.count == 1)
        #expect(adopted.blocks[0].adoptionScope == .occurrence)
        #expect(adopted.rules.isEmpty)

        let nextWeek = occurrence(recurrence: "series-a", startOffset: 7 * 24 * 3600)
        let refreshed = TimetableAdoption.refreshCalendarMembership(
            occurrences: [occ, nextWeek],
            membership: adopted
        )
        #expect(refreshed.blocks.filter(\.isActive).count == 1)
        #expect(refreshed.blocks[0].startsAt == occ.startsAt)
    }

    @Test func adoptSeries_insertsFutureOccurrences() {
        let first = occurrence(recurrence: "series-a")
        let second = occurrence(recurrence: "series-a", title: "週次", startOffset: 7 * 24 * 3600)
        var membership = TimetableAdoption.adoptOccurrence(
            first,
            scope: .series,
            membership: TimetableMembership(blocks: [], rules: [])
        )
        membership = TimetableAdoption.refreshCalendarMembership(
            occurrences: [first, second],
            membership: membership
        )
        #expect(membership.rules.count == 1)
        #expect(membership.rules[0].adopted)
        #expect(membership.blocks.filter(\.isActive).count == 2)
    }

    @Test func seriesExcludedOccurrence_isNotInserted() {
        let first = occurrence(recurrence: "series-a")
        let second = occurrence(recurrence: "series-a", startOffset: 7 * 24 * 3600)
        var membership = TimetableAdoption.adoptOccurrence(
            first,
            scope: .series,
            membership: TimetableMembership(blocks: [], rules: [])
        )
        membership = TimetableAdoption.refreshCalendarMembership(
            occurrences: [first, second],
            membership: membership
        )
        let secondBlock = membership.blocks.first { $0.startsAt == second.startsAt }!
        membership = TimetableAdoption.unadopt(
            blockID: secondBlock.id,
            scope: .occurrence,
            membership: membership
        )
        membership = TimetableAdoption.refreshCalendarMembership(
            occurrences: [first, second],
            membership: membership
        )
        let secondBlocks = membership.blocks.filter { $0.startsAt == second.startsAt }
        #expect(!secondBlocks.isEmpty)
        #expect(secondBlocks.allSatisfy { $0.isCancelled })
        #expect(membership.blocks.contains { $0.startsAt == first.startsAt && $0.isActive })
    }

    @Test func unadoptSeries_cancelsAllAndStopsFutureInserts() {
        let first = occurrence(recurrence: "series-a")
        let second = occurrence(recurrence: "series-a", startOffset: 7 * 24 * 3600)
        var membership = TimetableAdoption.adoptOccurrence(
            first,
            scope: .series,
            membership: TimetableMembership(blocks: [], rules: [])
        )
        membership = TimetableAdoption.refreshCalendarMembership(
            occurrences: [first, second],
            membership: membership
        )
        membership = TimetableAdoption.unadopt(
            blockID: membership.blocks[0].id,
            scope: .series,
            membership: membership
        )
        membership = TimetableAdoption.refreshCalendarMembership(
            occurrences: [first, second],
            membership: membership
        )
        #expect(membership.blocks.allSatisfy { $0.isCancelled })
        #expect(membership.rules[0].adopted == false)
    }

    @Test func calendarTimeChange_marksNeedsReview() {
        let occ = occurrence()
        var membership = TimetableAdoption.adoptOccurrence(
            occ,
            scope: .occurrence,
            membership: TimetableMembership(blocks: [], rules: [])
        )
        let moved = occurrence(startOffset: 600)
        membership = TimetableAdoption.refreshCalendarMembership(
            occurrences: [moved],
            membership: membership
        )
        #expect(membership.blocks[0].needsReview)
        #expect(membership.blocks[0].startsAt == moved.startsAt)
        #expect(membership.blocks[0].isActive)
    }
}
