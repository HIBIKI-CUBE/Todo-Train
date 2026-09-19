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
        try manager.extend(by: 180, reason: "仕事が膨らんだ")

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
            SessionExtension(addedSeconds: 120, reason: "まだかかる", session: arrived)
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
}
