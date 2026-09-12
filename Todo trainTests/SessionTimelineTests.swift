//
//  SessionTimelineTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct SessionTimelineTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(hour: Int, minute: Int) -> Date {
        utcCalendar.date(
            from: DateComponents(year: 2026, month: 9, day: 8, hour: hour, minute: minute)
        )!
    }

    private func ride(
        id: UUID = UUID(),
        title: String = "A",
        start: Date,
        end: Date,
        estimate: Int,
        outcome: SessionOutcome = .arrived,
        extensions: [TimelineExtension] = [],
        pauses: [TimelinePause] = []
    ) -> TimelineRide {
        TimelineRide(
            id: id,
            title: title,
            startedAt: start,
            endedAt: end,
            estimatedSecondsAtStart: estimate,
            outcome: outcome,
            punctuality: .notApplicable,
            extensions: extensions,
            pauses: pauses,
            transfers: []
        )
    }

    @Test func idleGap_usesSamePointsPerMinute() throws {
        let first = ride(
            start: date(hour: 9, minute: 0),
            end: date(hour: 9, minute: 30),
            estimate: 30 * 60
        )
        let second = ride(
            start: date(hour: 11, minute: 0),
            end: date(hour: 11, minute: 15),
            estimate: 15 * 60
        )
        let layout = try #require(
            SessionTimeline.layout(rides: [first, second], calendar: utcCalendar)
        )

        let gap = layout.y(for: second.startedAt) - layout.y(for: first.endedAt)
        #expect(gap == 90 * SessionTimeline.pointsPerMinute)
        #expect(layout.height == 180 * SessionTimeline.pointsPerMinute)
        #expect(layout.laneCount == 1)
        #expect(layout.start == date(hour: 9, minute: 0))
        #expect(layout.end == date(hour: 12, minute: 0))
    }

    @Test func stretchedEnd_fillsViewportWithoutChangingEventScale() throws {
        let sample = ride(
            start: date(hour: 9, minute: 0),
            end: date(hour: 10, minute: 0),
            estimate: 60 * 60
        )
        let layout = try #require(
            SessionTimeline.layout(
                rides: [sample],
                calendar: utcCalendar,
                minHeight: 300
            )
        )
        #expect(layout.height == 300)
        #expect(layout.y(for: sample.endedAt) == 60 * SessionTimeline.pointsPerMinute)
        #expect(
            SessionTimeline.stretchedEnd(
                start: date(hour: 9, minute: 0),
                end: date(hour: 10, minute: 0),
                minHeight: 0,
                pointsPerMinute: SessionTimeline.pointsPerMinute
            ) == date(hour: 10, minute: 0)
        )
    }

    @Test func overlappingRides_takeParallelLanes() throws {
        let a = ride(
            start: date(hour: 9, minute: 0),
            end: date(hour: 10, minute: 30),
            estimate: 45 * 60
        )
        let b = ride(
            start: date(hour: 9, minute: 35),
            end: date(hour: 10, minute: 0),
            estimate: 20 * 60
        )
        let layout = try #require(
            SessionTimeline.layout(rides: [a, b], calendar: utcCalendar)
        )
        #expect(layout.laneCount == 2)
        #expect(layout.laneIndex(for: a.id) != layout.laneIndex(for: b.id))
    }

    @Test func sequentialRides_reuseLane() throws {
        let a = ride(
            start: date(hour: 9, minute: 0),
            end: date(hour: 9, minute: 30),
            estimate: 30 * 60
        )
        let b = ride(
            start: date(hour: 9, minute: 30),
            end: date(hour: 9, minute: 50),
            estimate: 20 * 60
        )
        let layout = try #require(
            SessionTimeline.layout(rides: [a, b], calendar: utcCalendar)
        )
        #expect(layout.laneCount == 1)
        #expect(layout.laneIndex(for: a.id) == 0)
        #expect(layout.laneIndex(for: b.id) == 0)
    }

    @Test func isolatedRide_doesNotOverlapNeighbors() {
        let a = ride(
            start: date(hour: 9, minute: 0),
            end: date(hour: 9, minute: 30),
            estimate: 30 * 60
        )
        let b = ride(
            start: date(hour: 10, minute: 0),
            end: date(hour: 10, minute: 20),
            estimate: 20 * 60
        )
        #expect(SessionTimeline.rideIsIsolated(a, among: [a, b]))
        #expect(SessionTimeline.rideIsIsolated(b, among: [a, b]))
        #expect(!SessionTimeline.ridesOverlap(a, b))
    }

    @Test func overlappingRides_areNotIsolated() {
        let a = ride(
            start: date(hour: 9, minute: 0),
            end: date(hour: 10, minute: 30),
            estimate: 45 * 60
        )
        let b = ride(
            start: date(hour: 9, minute: 35),
            end: date(hour: 10, minute: 0),
            estimate: 20 * 60
        )
        #expect(!SessionTimeline.rideIsIsolated(a, among: [a, b]))
        #expect(!SessionTimeline.rideIsIsolated(b, among: [a, b]))
        #expect(SessionTimeline.ridesOverlap(a, b))
    }

    @Test func range_includesOriginalScheduleAfterEarlyArrival() throws {
        let early = ride(
            start: date(hour: 9, minute: 0),
            end: date(hour: 9, minute: 20),
            estimate: 60 * 60
        )
        let range = try #require(SessionTimeline.timeRange(rides: [early]))
        #expect(range.start == date(hour: 9, minute: 0))
        #expect(range.end == date(hour: 10, minute: 0))
    }

    @Test func markers_includeStartScheduleExtensionsPauseAndArrival() {
        let start = date(hour: 9, minute: 0)
        let sample = ride(
            start: start,
            end: date(hour: 10, minute: 20),
            estimate: 45 * 60,
            extensions: [
                TimelineExtension(
                    id: UUID(),
                    addedSeconds: 10 * 60,
                    reason: "割り込みが入った",
                    createdAt: date(hour: 9, minute: 40)
                ),
                TimelineExtension(
                    id: UUID(),
                    addedSeconds: 5 * 60,
                    reason: nil,
                    createdAt: date(hour: 9, minute: 55)
                )
            ],
            pauses: [
                TimelinePause(
                    id: UUID(),
                    startedAt: date(hour: 9, minute: 50),
                    endedAt: date(hour: 10, minute: 5)
                )
            ]
        )
        let markers = SessionTimeline.markers(for: sample)
        #expect(markers.map(\.kind) == [
            .boarded,
            .extensionStep(index: 1, addedSeconds: 600, reason: "割り込みが入った"),
            .originalSchedule,
            .pause,
            .extensionStep(index: 2, addedSeconds: 300, reason: nil),
            .arrived
        ])
        #expect(SessionTimeline.markerLabel(markers[1]) == "延長1 +10分")
        #expect(SessionTimeline.markerLabel(markers[3]) == "停車 15分")
        #expect(SessionTimeline.markerLabel(markers[4]) == "延長2 +5分")
    }

    @Test func layout_snapsCanvasToHourMarks() throws {
        let sample = ride(
            start: date(hour: 9, minute: 20),
            end: date(hour: 11, minute: 10),
            estimate: 30 * 60
        )
        let layout = try #require(
            SessionTimeline.layout(rides: [sample], calendar: utcCalendar)
        )
        #expect(layout.start == date(hour: 9, minute: 0))
        #expect(layout.end == date(hour: 12, minute: 0))
        let hours = layout.hourTicks.map { utcCalendar.component(.hour, from: $0) }
        #expect(hours == [9, 10, 11, 12])
    }

    @Test func hourAlignedRange_keepsExactHourEnd() {
        let range = SessionTimeline.hourAlignedRange(
            start: date(hour: 9, minute: 0),
            end: date(hour: 11, minute: 0),
            calendar: utcCalendar
        )
        #expect(range.start == date(hour: 9, minute: 0))
        #expect(range.end == date(hour: 11, minute: 0))
    }

    @Test func ridesFromSessions_mapsPauseAndExtension() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "報告書", estimatedSeconds: 45 * 60)
        context.insert(ticket)
        let start = date(hour: 9, minute: 0)
        let session = WorkSession(startedAt: start, estimatedSecondsAtStart: 45 * 60, ticket: ticket)
        session.endedAt = date(hour: 10, minute: 0)
        session.accumulatedActiveSeconds = 40 * 60
        session.outcome = .arrived
        context.insert(session)
        context.insert(
            SessionExtension(
                addedSeconds: 10 * 60,
                createdAt: date(hour: 9, minute: 20),
                session: session
            )
        )
        context.insert(
            SessionPause(
                startedAt: date(hour: 9, minute: 30),
                endedAt: date(hour: 9, minute: 40),
                session: session
            )
        )

        let rides = SessionTimeline.rides(from: [session])
        #expect(rides.count == 1)
        #expect(rides.first?.extensions.count == 1)
        #expect(rides.first?.pauses.count == 1)
        #expect(rides.first?.originalScheduleAt == date(hour: 9, minute: 45))
    }

    @Test func previewSeed_keepsIdleAtFullScale() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        HistoryPreviewSeed.insertSampleDay(into: context, calendar: utcCalendar)
        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        let rides = SessionTimeline.rides(from: sessions)
        let layout = try #require(
            SessionTimeline.layout(rides: rides, calendar: utcCalendar)
        )
        let sorted = rides.sorted { $0.startedAt < $1.startedAt }
        #expect(sorted.count == 2)
        let gap = layout.y(for: sorted[1].startedAt) - layout.y(for: sorted[0].endedAt)
        #expect(gap == 90 * SessionTimeline.pointsPerMinute)
    }
}
