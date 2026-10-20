//
//  ServiceCabinSequenceTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct ServiceCabinSequenceTests {
    @Test func lamp_holdsDarkBeforeFirstLight() {
        #expect(ServiceCabinSequence.lamp(elapsed: 0, reduceMotion: false) == .dark)
        #expect(
            ServiceCabinSequence.lamp(
                elapsed: ServiceCabinSequence.darkHoldSeconds - 0.01,
                reduceMotion: false
            ) == .dark
        )
    }

    @Test func lamp_stepsThroughPanelsAfterHold() {
        let hold = ServiceCabinSequence.darkHoldSeconds
        let test = ServiceCabinSequence.testHoldSeconds
        let live = ServiceCabinSequence.liveHoldSeconds
        #expect(ServiceCabinSequence.lamp(elapsed: hold, reduceMotion: false) == .test)
        #expect(ServiceCabinSequence.lamp(elapsed: hold + test, reduceMotion: false) == .live)
        #expect(ServiceCabinSequence.lamp(elapsed: hold + test + live, reduceMotion: false) == .ready)
        #expect(ServiceCabinSequence.lamp(elapsed: hold + test + live + 40, reduceMotion: false) == .ready)
    }

    @Test func lamp_reduceMotionJumpsToReady() {
        #expect(ServiceCabinSequence.lamp(elapsed: 0, reduceMotion: true) == .ready)
    }

    @Test func shutdown_reversesPanels() {
        let step = ServiceCabinSequence.stepSeconds
        #expect(ServiceCabinSequence.shutdownLamp(elapsed: 0, reduceMotion: false) == .ready)
        #expect(ServiceCabinSequence.shutdownLamp(elapsed: step + 0.001, reduceMotion: false) == .live)
        #expect(ServiceCabinSequence.shutdownLamp(elapsed: step * 3 + 0.001, reduceMotion: false) == .dark)
        #expect(ServiceCabinSequence.shutdownLamp(elapsed: 0, reduceMotion: true) == .dark)
    }

    @Test func annunciators_allOnDuringLampTest() {
        for id in ServiceCabinAnnunciator.allCases {
            #expect(
                ServiceCabinSequence.annunciatorLit(
                    id,
                    lamp: .test,
                    serviceOn: false,
                    hasOccupancy: false,
                    paused: false
                )
            )
        }
    }

    @Test func annunciators_followLiveStateAfterTest() {
        #expect(
            ServiceCabinSequence.annunciatorLit(
                .service,
                lamp: .live,
                serviceOn: true,
                hasOccupancy: false,
                paused: false
            )
        )
        #expect(
            !ServiceCabinSequence.annunciatorLit(
                .occupancy,
                lamp: .ready,
                serviceOn: true,
                hasOccupancy: false,
                paused: false
            )
        )
        #expect(
            ServiceCabinSequence.annunciatorLit(
                .paused,
                lamp: .ready,
                serviceOn: true,
                hasOccupancy: true,
                paused: true
            )
        )
        #expect(
            !ServiceCabinSequence.annunciatorLit(
                .service,
                lamp: .dark,
                serviceOn: true,
                hasOccupancy: true,
                paused: true
            )
        )
    }

    @Test func annunciators_clickOnDuringLampTest() {
        #expect(
            ServiceCabinSequence.annunciatorLit(
                .service,
                lamp: .test,
                serviceOn: false,
                hasOccupancy: false,
                paused: false,
                testCount: 1
            )
        )
        #expect(
            !ServiceCabinSequence.annunciatorLit(
                .occupancy,
                lamp: .test,
                serviceOn: false,
                hasOccupancy: false,
                paused: false,
                testCount: 1
            )
        )
        #expect(
            ServiceCabinSequence.annunciatorLit(
                .occupancy,
                lamp: .test,
                serviceOn: false,
                hasOccupancy: false,
                paused: false,
                testCount: 2
            )
        )
    }

    @Test func secondsRailRest_isMinuteFraction() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 18, hour: 7, minute: 5, second: 30)
        )!
        #expect(abs(ServiceCabinSequence.secondsRailRest(at: date, calendar: calendar) - 0.5) < 0.0001)
    }

    @Test func annunciators_stayLitUntilThatCellSettles() {
        #expect(
            ServiceCabinSequence.annunciatorLit(
                .occupancy,
                lamp: .live,
                serviceOn: true,
                hasOccupancy: false,
                paused: false,
                settledCount: 1
            )
        )
        #expect(
            !ServiceCabinSequence.annunciatorLit(
                .occupancy,
                lamp: .live,
                serviceOn: true,
                hasOccupancy: false,
                paused: false,
                settledCount: 2
            )
        )
    }

    @Test func clockDigits_areAlwaysValidTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 18, hour: 7, minute: 5, second: 9)
        )!
        let parts = ServiceCabinSequence.clockDigits(at: date, calendar: calendar)
        #expect(parts.hourMinute == "07:05")
        #expect(parts.second == "09")
    }

    @Test func tapeRest_usesCurrentSpanOrNextPosition() {
        let current = [
            TimetableOccupancyMark(
                id: UUID(),
                position: 0,
                span: 0.4,
                isCurrent: true,
                isAdopted: true
            )
        ]
        #expect(abs(ServiceCabinSequence.tapeRest(marks: current) - 0.4) < 0.0001)

        let next = [
            TimetableOccupancyMark(
                id: UUID(),
                position: 0.55,
                span: 0,
                isCurrent: false,
                isAdopted: true
            )
        ]
        #expect(abs(ServiceCabinSequence.tapeRest(marks: next) - 0.55) < 0.0001)
        #expect(ServiceCabinSequence.tapeRest(marks: []) == 0)
    }

    @Test func morningNotices_skipRowsAlreadyOnOccupancy() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let current = CalendarOccurrence(
            eventIdentifier: "now",
            title: "会議",
            startsAt: now.addingTimeInterval(-600),
            endsAt: now.addingTimeInterval(600),
            isAllDay: false,
            isDeclined: false
        )
        let later = CalendarOccurrence(
            eventIdentifier: "later",
            title: "原稿",
            startsAt: now.addingTimeInterval(3600),
            endsAt: now.addingTimeInterval(5400),
            isAllDay: false,
            isDeclined: false
        )
        let row = TimetableFit.occupancyRow(for: current, now: now, calendar: calendar)
        let notices = ServiceCabinSequence.morningNotices(
            remaining: [current, later],
            occupancyRows: [row],
            now: now
        )
        #expect(notices.map(\.title) == ["原稿"])
    }

    @Test func morningNotices_capsRemaining() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var notices: [CalendarOccurrence] = []
        for index in 0..<6 {
            let start = now.addingTimeInterval(TimeInterval(index + 1) * 3600)
            notices.append(
                CalendarOccurrence(
                    eventIdentifier: "e\(index)",
                    title: "N\(index)",
                    startsAt: start,
                    endsAt: start.addingTimeInterval(1800),
                    isAllDay: false,
                    isDeclined: false
                )
            )
        }
        let kept = ServiceCabinSequence.morningNotices(
            remaining: notices,
            occupancyRows: [],
            now: now
        )
        #expect(kept.count == ServiceCabinSequence.morningNoticeLimit)
        #expect(kept.first?.title == "N0")
    }

    @Test func dayFacts_alwaysIncludeFocus() {
        let facts = ServiceCabinSequence.dayFacts(in: [])
        #expect(facts.map(\.label) == ["集中"])
        #expect(facts.first?.value == "0分")
    }
}

@MainActor
struct ServiceCabinExtensionTests {
    @Test func unlabeledExtensions_skipsFilledReasons() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        try manager.extend(by: 300, reason: nil)
        try manager.extend(by: 180, reason: "作業増")

        let session = try #require(manager.activeSession)
        let unlabeled = ServiceCabinSequence.unlabeledExtensions(in: [session])
        #expect(unlabeled.count == 1)
        #expect(unlabeled.first?.addedSeconds == 300)
        #expect(ServiceCabinSequence.extensionMinutes(in: [session]) == 8)
    }

    @Test func setExtensionReason_writesAfterTheRide() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        try manager.extend(by: 300)

        let session = try #require(manager.activeSession)
        let unlabeled = try #require(ServiceCabinSequence.unlabeledExtensions(in: [session]).first)
        manager.setExtensionReason("割り込みが入った", on: unlabeled)
        #expect(unlabeled.reason == "割り込みが入った")
        #expect(ServiceCabinSequence.unlabeledExtensions(in: [session]).isEmpty)
    }

    @Test func dayFacts_includeNonzeroRecords() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "T", estimatedSeconds: 600)
        context.insert(ticket)

        let arrived = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        arrived.accumulatedActiveSeconds = 600
        arrived.endedAt = .now
        arrived.outcome = .arrived
        context.insert(arrived)
        arrived.extensions.append(
            SessionExtension(addedSeconds: 120, reason: "見積もり不足", session: arrived)
        )

        let partial = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: ticket)
        partial.accumulatedActiveSeconds = 60
        partial.endedAt = .now
        partial.outcome = .partialDisembark
        context.insert(partial)

        let facts = ServiceCabinSequence.dayFacts(in: [arrived, partial])
        #expect(facts.contains { $0.label == "集中" && $0.value == "11分" })
        #expect(facts.contains { $0.label == "延長" && $0.value == "2分" })
        #expect(facts.contains { $0.label == "到着" && $0.value == "1" })
        #expect(facts.contains { $0.label == "途中下車" && $0.value == "1" })
        #expect(!facts.contains { $0.label == "放棄" })
    }

    @Test func consistItems_skipsClosedAndOrders() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let closed = Ticket(title: "済", estimatedSeconds: 600, sortOrder: 0)
        closed.closedAt = .now
        let later = Ticket(title: "後", estimatedSeconds: 25 * 60, sortOrder: 2)
        let earlier = Ticket(title: "先", estimatedSeconds: 90, sortOrder: 1)
        context.insert(closed)
        context.insert(later)
        context.insert(earlier)

        let items = ServiceCabinSequence.consistItems(from: [closed, later, earlier])
        #expect(items.map(\.title) == ["先", "後"])
        #expect(items.map(\.minutes) == [1, 25])
    }

    @Test func annunciatorLegend_holdsAlertWordsUntilLive() {
        #expect(
            ServiceCabinSequence.annunciatorLegend(
                .occupancy,
                showsLiveReading: false,
                serviceOn: true,
                track: .clear,
                paused: false
            ) == "塞がり"
        )
        #expect(
            ServiceCabinSequence.annunciatorLegend(
                .service,
                showsLiveReading: true,
                serviceOn: true,
                track: .clear,
                paused: false
            ) == "運行中"
        )
        #expect(
            ServiceCabinSequence.annunciatorLegend(
                .service,
                showsLiveReading: true,
                serviceOn: false,
                track: .clear,
                paused: false
            ) == "運休"
        )
        #expect(
            ServiceCabinSequence.annunciatorLegend(
                .paused,
                showsLiveReading: true,
                serviceOn: true,
                track: .clear,
                paused: false
            ) == "進行"
        )
        #expect(
            ServiceCabinSequence.annunciatorLegend(
                .paused,
                showsLiveReading: true,
                serviceOn: true,
                track: .clear,
                paused: true
            ) == "停車中"
        )
    }

    @Test func trackReading_distinguishesNowAndLater() {
        let now = TimetableOccupancyRow(
            id: UUID(),
            kind: .occupying,
            clock: "10:00",
            remainingMinutes: 20,
            title: "週次",
            spokenLine: "いま"
        )
        let later = TimetableOccupancyRow(
            id: UUID(),
            kind: .next,
            clock: "15:00",
            remainingMinutes: nil,
            title: "歯医者",
            spokenLine: "次"
        )
        #expect(ServiceCabinSequence.trackReading(rows: [now, later], marks: []) == .blocked)
        #expect(ServiceCabinSequence.trackReading(rows: [later], marks: []) == .scheduled)
        #expect(
            ServiceCabinSequence.annunciatorLegend(
                .occupancy,
                showsLiveReading: true,
                serviceOn: true,
                track: .scheduled,
                paused: false
            ) == "予定"
        )
        #expect(ServiceCabinSequence.trackReading(rows: [], marks: []) == .clear)
        #expect(
            ServiceCabinSequence.annunciatorLegend(
                .occupancy,
                showsLiveReading: true,
                serviceOn: true,
                track: .clear,
                paused: false
            ) == "空き"
        )
    }

    @Test func consistMoveOffset_landsOnVisualIndex() {
        #expect(ServiceCabinSequence.consistMoveOffset(from: 0, to: 2) == 3)
        #expect(ServiceCabinSequence.consistMoveOffset(from: 3, to: 1) == 1)
        #expect(ServiceCabinSequence.consistMoveOffset(from: 1, to: 1) == 1)
    }

    @Test func overview_fitsServiceWindowAndNotMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7))!
        let start = day.addingTimeInterval(10 * 3600)
        let now = day.addingTimeInterval(18 * 3600 + 30 * 60)
        let dayEnd = day.addingTimeInterval(86_400)
        let bounds = ServiceCabinOverview.serviceBounds(
            startedAt: start,
            now: now,
            dayStart: day,
            dayEnd: dayEnd,
            rides: [(start: day.addingTimeInterval(15 * 3600), end: day.addingTimeInterval(16 * 3600))]
        )
        #expect(bounds.start > day)
        #expect(bounds.end < dayEnd)
        #expect(bounds.start < start)

        let fitted = ServiceCabinOverview.fitted(
            bounds: bounds,
            viewportHeight: 420,
            calendar: calendar,
            slack: 10
        )
        #expect(fitted.start > day)
        #expect(fitted.pointsPerMinute <= SessionTimeline.pointsPerMinute)
        #expect(fitted.height + 10 <= 420 + 0.5)

        let wide = ServiceCabinOverview.fullDay(on: day, viewportHeight: 420, calendar: calendar, slack: 10)
        #expect(wide.start == day)
        #expect(abs(wide.height + 10 - 420) < 1)
        #expect(ServiceCabinOverview.hourStride(pointsPerMinute: wide.pointsPerMinute) > 1)
    }

    @Test func overview_shortServiceDoesNotExceedHistoryScale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7))!
        let start = day.addingTimeInterval(9 * 3600)
        let now = start.addingTimeInterval(20 * 60)
        let bounds = ServiceCabinOverview.serviceBounds(
            startedAt: start,
            now: now,
            dayStart: day,
            dayEnd: day.addingTimeInterval(86_400),
            rides: []
        )
        #expect(bounds.end.timeIntervalSince(bounds.start) >= ServiceCabinOverview.minimumSpan - 1)
        let fitted = ServiceCabinOverview.fitted(
            bounds: bounds,
            viewportHeight: 800,
            calendar: calendar,
            slack: 10
        )
        #expect(abs(fitted.pointsPerMinute - SessionTimeline.pointsPerMinute) < 0.001)
        #expect(fitted.height < 800)
    }
}
