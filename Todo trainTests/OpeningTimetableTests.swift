//
//  OpeningTimetableTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct OpeningTimetableLayoutTests {
    private let dayStart = Date(timeIntervalSince1970: 1_699_920_000)
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func at(hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        utc.date(byAdding: .second, value: hour * 3600 + minute * 60 + second, to: dayStart)!
    }

    private func entry(
        _ title: String,
        startHour: Int,
        startMinute: Int = 0,
        endHour: Int,
        endMinute: Int = 0,
        stops: Bool
    ) -> OpeningTimetableEntry {
        let id = UUID()
        return OpeningTimetableEntry(
            kind: stops ? .stop(blockID: id) : .passManual(blockID: id),
            title: title,
            startsAt: at(hour: startHour, minute: startMinute),
            endsAt: at(hour: endHour, minute: endMinute)
        )
    }

    private var range: TimetableRange {
        TimetableRange(
            startsAt: at(hour: 9),
            endsAt: at(hour: 19),
            spanHours: 10,
            windowLabel: "09–19 10H"
        )
    }

    @Test func isolatedRowStaysOnTheBandCenter() {
        let frames = TimetableColumnLayout.rowFrames(
            entries: [entry("定例", startHour: 12, endHour: 13, stops: true)],
            range: range,
            height: 200
        )
        #expect(frames.count == 1)
        #expect(abs(frames[0].top - 53) < 0.2)
        #expect(abs(frames[0].rowCenter - frames[0].bandCenter) < 0.2)
    }

    @Test func overlappingRowsShiftApartAndKeepAGap() {
        let frames = TimetableColumnLayout.rowFrames(
            entries: [
                entry("朝会", startHour: 10, endHour: 10, endMinute: 20, stops: true),
                entry("電話", startHour: 10, startMinute: 10, endHour: 10, endMinute: 30, stops: false),
            ],
            range: range,
            height: 200
        )
        #expect(frames.count == 2)
        let gap = frames[1].top - (frames[0].top + TimetableColumnLayout.rowHeight)
        #expect(gap >= TimetableColumnLayout.rowGap - 0.05)
        #expect(abs(frames[1].rowCenter - frames[1].bandCenter) > 1)
    }

    @Test func distantRowsStayOnTheirOwnCenters() {
        let frames = TimetableColumnLayout.rowFrames(
            entries: [
                entry("定例", startHour: 10, endHour: 11, stops: true),
                entry("歯医者", startHour: 15, endHour: 16, stops: true),
            ],
            range: range,
            height: 200
        )
        #expect(abs(frames[0].rowCenter - frames[0].bandCenter) < 0.2)
        #expect(abs(frames[1].rowCenter - frames[1].bandCenter) < 0.2)
        #expect(frames[1].top - frames[0].top > TimetableColumnLayout.rowHeight)
    }

    @Test func nameLengthFollowsTheHeightThresholds() {
        #expect(RunStatusColumnLayout.name(for: .normal, height: 24) == "平常運転")
        #expect(RunStatusColumnLayout.name(for: .normal, height: 23.9) == "平常")
        #expect(RunStatusColumnLayout.name(for: .dense, height: 13) == "過密")
        #expect(RunStatusColumnLayout.name(for: .dense, height: 24) == "ダイヤ過密")
        #expect(RunStatusColumnLayout.name(for: .hold, height: 13) == "見合せ")
        #expect(RunStatusColumnLayout.name(for: .hold, height: 12.99) == nil)
        #expect(RunStatusColumnLayout.name(for: .hold, height: 24) == "見合わせ")
    }

    @Test func passingStopIsNotTheNowBandOrTheNextRide() {
        let adopted = [
            TimetableOpeningInterval(startsAt: at(hour: 9, minute: 30), endsAt: at(hour: 9, minute: 45)),
            TimetableOpeningInterval(startsAt: at(hour: 10), endsAt: at(hour: 11)),
            TimetableOpeningInterval(startsAt: at(hour: 16, minute: 30), endsAt: at(hour: 18, minute: 30)),
        ]
        let now = at(hour: 13, minute: 10)
        let next = RunStatusLogic.nextMarkers(now: now, adoptedBlocks: adopted)
        #expect(next.nextRideInTarget == nil)
        #expect(next.nextStopInTarget == at(hour: 16, minute: 30))
        let span = TimetableColumnLayout.nowSpan(now: now, range: range, next: next)
        #expect(span?.insideStop == false)
        #expect(span?.startsAt == now)
        #expect(span?.endsAt == at(hour: 16, minute: 30))

        let beforeFirst = RunStatusLogic.nextMarkers(now: at(hour: 8, minute: 30), adoptedBlocks: adopted)
        let early = TimetableColumnLayout.nowSpan(now: at(hour: 8, minute: 30), range: range, next: beforeFirst)
        #expect(early?.startsAt == at(hour: 9))
        #expect(early?.endsAt == at(hour: 9, minute: 30))
        #expect(early?.insideStop == false)

        let withPhone = adopted + [
            TimetableOpeningInterval(startsAt: at(hour: 13), endsAt: at(hour: 13, minute: 30)),
        ]
        let riding = RunStatusLogic.nextMarkers(now: now, adoptedBlocks: withPhone)
        #expect(riding.nextRideInTarget == at(hour: 13, minute: 30))
        #expect(riding.nextStopInTarget == nil)
    }

    @Test func nextReadoutTicksInSecondsAndDimsTheIdleSide() {
        let outside = RunStatusNext(
            currentBandEndsAt: nil,
            nextStopInTarget: at(hour: 16, minute: 30),
            nextRideInTarget: nil
        )
        let stop = TimetableNextReadout.make(now: at(hour: 13, minute: 10), next: outside)
        #expect(stop.stopText == "03:20:00")
        #expect(stop.rideText == "--:--:--")
        #expect(stop.stopLit)
        #expect(!stop.rideLit)

        let inside = RunStatusNext(
            currentBandEndsAt: at(hour: 13, minute: 30),
            nextStopInTarget: nil,
            nextRideInTarget: at(hour: 13, minute: 30)
        )
        let ride = TimetableNextReadout.make(now: at(hour: 13, minute: 10, second: 5), next: inside)
        #expect(ride.rideText == "00:19:55")
        #expect(ride.stopText == "--:--:--")
        #expect(ride.rideLit)
        #expect(!ride.stopLit)
    }
}

@MainActor
struct OpeningTimetableToggleTests {
    private let dayStart = Date(timeIntervalSince1970: 1_699_920_000)
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func at(hour: Int, minute: Int = 0) -> Date {
        utc.date(byAdding: .minute, value: hour * 60 + minute, to: dayStart)!
    }

    @Test func toggleStop_rewritesBandsReadingAndLoad() throws {
        let now = at(hour: 13, minute: 10)
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: now, calendar: utc)
        func block(_ title: String, _ start: Date, _ end: Date) {
            context.insert(TimetableBlock(title: title, startsAt: start, endsAt: end, source: .manual))
        }
        block("朝会", at(hour: 9, minute: 30), at(hour: 9, minute: 45))
        block("定例ミーティング", at(hour: 10), at(hour: 11))
        block("電話", at(hour: 13), at(hour: 13, minute: 30))
        block("歯医者", at(hour: 16, minute: 30), at(hour: 18, minute: 30))
        try context.save()

        let tickets = [ServiceLoadTicket(durationMinutes: 45)]
        let before = manager.openingTimetableBoard(now: now, ticketsAboveCutoff: tickets)
        let phone = try #require(before.entries.first { $0.title == "電話" })
        #expect(phone.stops)
        #expect(before.range.windowLabel == "09–19 10H")
        #expect(before.bands.contains { $0.kind == .hold && $0.startsAt == at(hour: 13) && $0.endsAt == at(hour: 13, minute: 30) })
        if case .waitingForNormal(let status, let until, _) = before.reading.caseKind {
            #expect(status == .hold)
            #expect(until == 20)
        } else {
            Issue.record("着発した電話のあいだは見合わせ")
        }

        manager.toggleOpeningTimetableStop(phone)

        let after = manager.openingTimetableBoard(now: now, ticketsAboveCutoff: tickets)
        let passed = try #require(after.entries.first { $0.title == "電話" })
        #expect(!passed.stops)
        #expect(after.bands.contains {
            $0.kind == .normal && $0.startsAt == at(hour: 11) && $0.endsAt == at(hour: 16, minute: 30)
        })
        #expect(!after.bands.contains { $0.startsAt == at(hour: 13) && $0.endsAt == at(hour: 13, minute: 30) })
        #expect(after.load.freeMinutes == before.load.freeMinutes + 20)
        #expect(after.load.ticketMinutes == 45)
        #expect(after.next.nextRideInTarget == nil)
        #expect(after.next.nextStopInTarget == at(hour: 16, minute: 30))
        let span = TimetableColumnLayout.nowSpan(now: now, range: after.range, next: after.next)
        #expect(span?.endsAt == at(hour: 16, minute: 30))
        #expect(span?.insideStop == false)
        if case .ridingNormal(let remaining, let endsAt) = after.reading.caseKind {
            #expect(remaining == 200)
            #expect(endsAt == at(hour: 16, minute: 30))
        } else {
            Issue.record("通過にしたあとは平常運転")
        }

        manager.toggleOpeningTimetableStop(passed)
        let restored = manager.openingTimetableBoard(now: now, ticketsAboveCutoff: tickets)
        #expect(restored.entries.first { $0.title == "電話" }?.stops == true)
        #expect(restored.load.freeMinutes == before.load.freeMinutes)
        #expect(restored.bands.contains { $0.kind == .hold && $0.startsAt == at(hour: 13) })
    }

    @Test func toggleSeriesStop_appliesToThisOccurrenceOnly() async throws {
        let board = InMemoryCalendarBoard()
        let first = CalendarOccurrence(
            eventIdentifier: "weekly",
            recurrenceIdentifier: "series-1",
            title: "週次",
            startsAt: at(hour: 10),
            endsAt: at(hour: 11),
            isAllDay: false,
            isDeclined: false,
            calendarIdentifier: "work",
            calendarTitle: "仕事"
        )
        board.events = [first]
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(
            now: at(hour: 9),
            calendar: utc,
            calendarBoard: board
        )
        await manager.refreshCalendarBoard()
        manager.adoptOccurrence(first, scope: .series)
        let adopted = manager.openingTimetableBoard(now: at(hour: 9))
        let entry = try #require(adopted.entries.first { $0.title == "週次" })
        #expect(entry.stops)

        manager.toggleOpeningTimetableStop(entry)

        let rule = try #require(manager.fetchSeriesRules().first)
        #expect(rule.adopted)
        #expect(rule.excludes(start: first.startsAt))
        #expect(manager.fetchActiveTimetableBlocks().isEmpty)
        let passed = manager.openingTimetableBoard(now: at(hour: 9))
        #expect(passed.entries.first { $0.title == "週次" }?.stops == false)

        let nextWeek = CalendarOccurrence(
            eventIdentifier: "weekly",
            recurrenceIdentifier: "series-1",
            title: "週次",
            startsAt: at(hour: 10).addingTimeInterval(7 * 86_400),
            endsAt: at(hour: 11).addingTimeInterval(7 * 86_400),
            isAllDay: false,
            isDeclined: false,
            calendarIdentifier: "work",
            calendarTitle: "仕事"
        )
        let membership = TimetableMembership(
            blocks: manager.fetchTimetableBlocks().map { block in
                TimetableBlockRecord(
                    id: block.id,
                    title: block.title,
                    startsAt: block.startsAt,
                    endsAt: block.endsAt,
                    source: block.source,
                    adoptionScope: block.adoptionScope,
                    isCancelled: block.isCancelled,
                    needsReview: block.needsReview,
                    calendarEventIdentifier: block.calendarEventIdentifier,
                    calendarRecurrenceIdentifier: block.calendarRecurrenceIdentifier,
                    occurrenceStartKey: block.occurrenceStartKey
                )
            },
            rules: manager.fetchSeriesRules().map { rule in
                TimetableSeriesRecord(
                    id: rule.id,
                    recurrenceIdentifier: rule.recurrenceIdentifier,
                    title: rule.title,
                    adopted: rule.adopted,
                    excludedOccurrenceStarts: rule.excludedOccurrenceStarts
                )
            }
        )
        #expect(TimetableAdoption.isAdopted(occurrence: nextWeek, membership: membership))
        #expect(!TimetableAdoption.isAdopted(occurrence: first, membership: membership))
    }
}

