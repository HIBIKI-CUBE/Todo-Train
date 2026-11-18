//
//  RunStatusTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

@MainActor
struct RunStatusTests {
    // 2023-11-14 00:00:00 UTC（utc の日の始まりに揃える）
    private let dayStart = Date(timeIntervalSince1970: 1_699_920_000)
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func at(hour: Int, minute: Int = 0) -> Date {
        utc.date(byAdding: .minute, value: hour * 60 + minute, to: dayStart)!
    }

    private func interval(
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int
    ) -> TimetableOpeningInterval {
        TimetableOpeningInterval(startsAt: at(hour: startHour, minute: startMinute), endsAt: at(hour: endHour, minute: endMinute))
    }

  private var stdScheduled: [TimetableOpeningInterval] {
    [
      interval(startHour: 9, startMinute: 30, endHour: 9, endMinute: 45),
      interval(startHour: 10, startMinute: 0, endHour: 11, endMinute: 0),
      interval(startHour: 13, startMinute: 0, endHour: 13, endMinute: 30),
      interval(startHour: 16, startMinute: 30, endHour: 18, endMinute: 30),
    ]
  }

  private var stdAdopted: [TimetableOpeningInterval] {
    [
      interval(startHour: 9, startMinute: 30, endHour: 9, endMinute: 45),
      interval(startHour: 10, startMinute: 0, endHour: 11, endMinute: 0),
      interval(startHour: 16, startMinute: 30, endHour: 18, endMinute: 30),
    ]
  }

  private var packedScheduled: [TimetableOpeningInterval] {
    [
      interval(startHour: 8, startMinute: 0, endHour: 8, endMinute: 15),
      interval(startHour: 8, startMinute: 15, endHour: 8, endMinute: 30),
      interval(startHour: 8, startMinute: 45, endHour: 9, endMinute: 0),
      interval(startHour: 9, startMinute: 0, endHour: 10, endMinute: 0),
      interval(startHour: 10, startMinute: 0, endHour: 10, endMinute: 20),
      interval(startHour: 10, startMinute: 30, endHour: 11, endMinute: 30),
    ]
  }

  private var packedAdopted: [TimetableOpeningInterval] {
    [
      interval(startHour: 8, startMinute: 0, endHour: 8, endMinute: 15),
      interval(startHour: 8, startMinute: 15, endHour: 8, endMinute: 30),
      interval(startHour: 9, startMinute: 0, endHour: 10, endMinute: 0),
      interval(startHour: 10, startMinute: 0, endHour: 10, endMinute: 20),
    ]
  }

  @Test func timetableRange_stdDayMatchesSpecWindow() {
    let range = TimetableRangeLogic.compute(
      scheduledBlocks: stdScheduled,
      referenceDay: dayStart,
      calendar: utc
    )
    #expect(range.windowLabel == "09–19 10H")
    #expect(range.startsAt == at(hour: 9))
    #expect(range.endsAt == at(hour: 19))
  }

  @Test func timetableRange_eveningThroughMidnight() {
    let blocks = [
      TimetableOpeningInterval(
        startsAt: at(hour: 20),
        endsAt: utc.date(byAdding: .day, value: 1, to: dayStart)!
      ),
    ]
    let range = TimetableRangeLogic.compute(scheduledBlocks: blocks, referenceDay: dayStart, calendar: utc)
    #expect(range.windowLabel == "20–24 4H")
    #expect(range.startsAt == at(hour: 20))
    #expect(range.endsAt == at(hour: 24))
  }

  @Test func timetableRange_lateNightShortEventExpandsToFourHours() {
    let blocks = [interval(startHour: 23, startMinute: 0, endHour: 23, endMinute: 30)]
    let range = TimetableRangeLogic.compute(scheduledBlocks: blocks, referenceDay: dayStart, calendar: utc)
    #expect(range.windowLabel == "20–24 4H")
    #expect(range.startsAt == at(hour: 20))
    #expect(range.endsAt == at(hour: 24))
  }

  @Test func timetableRange_crossMidnightFromPreviousDay() {
    let previousDay = utc.date(byAdding: .day, value: -1, to: dayStart)!
    let start = utc.date(byAdding: .hour, value: 23, to: previousDay)!
    let blocks = [
      TimetableOpeningInterval(startsAt: start, endsAt: at(hour: 1, minute: 30)),
    ]
    let range = TimetableRangeLogic.compute(scheduledBlocks: blocks, referenceDay: dayStart, calendar: utc)
    #expect(range.windowLabel == "00–04 4H")
    #expect(range.startsAt == at(hour: 0))
    #expect(range.endsAt == at(hour: 4))
  }

  @Test func runStatusBands_stdDayMatchesSpec() throws {
    let range = TimetableRangeLogic.compute(
      scheduledBlocks: stdScheduled,
      referenceDay: dayStart,
      calendar: utc
    )
    let bands = RunStatusLogic.bands(range: range, adoptedBlocks: stdAdopted)
    try #require(bands.count == 5)
    #expect(bands[0].kind == .dense)
    #expect(bands[0].startsAt == at(hour: 9) && bands[0].endsAt == at(hour: 10))
    #expect(bands[1].kind == .hold)
    #expect(bands[1].startsAt == at(hour: 10) && bands[1].endsAt == at(hour: 11))
    #expect(bands[2].kind == .normal)
    #expect(bands[2].startsAt == at(hour: 11) && bands[2].endsAt == at(hour: 16, minute: 30))
    #expect(bands[3].kind == .hold)
    #expect(bands[3].startsAt == at(hour: 16, minute: 30) && bands[3].endsAt == at(hour: 18, minute: 30))
    #expect(bands[4].kind == .dense)
    #expect(bands[4].startsAt == at(hour: 18, minute: 30) && bands[4].endsAt == at(hour: 19))
  }

  @Test func nowReading_stdDayExamples() {
    let range = TimetableRangeLogic.compute(
      scheduledBlocks: stdScheduled,
      referenceDay: dayStart,
      calendar: utc
    )
    let bands = RunStatusLogic.bands(range: range, adoptedBlocks: stdAdopted)

    let eightThirty = RunStatusLogic.nowReading(now: at(hour: 8, minute: 30), range: range, bands: bands)
    if case .beforeStart(minutesUntilNextNormal: 150, nextNormalDurationMinutes: 330) = eightThirty.caseKind {
      #expect(eightThirty.referencedNormalBand?.startsAt == at(hour: 11))
    } else {
      Issue.record("08:30 は始発前の言い方になるべき")
    }

    let nineFifty = RunStatusLogic.nowReading(now: at(hour: 9, minute: 50), range: range, bands: bands)
    if case .waitingForNormal(status: .dense, minutesUntilNextNormal: 70, nextNormalDurationMinutes: 330) =
      nineFifty.caseKind
    {
      #expect(nineFifty.referencedNormalBand?.startsAt == at(hour: 11))
    } else {
      Issue.record("09:50 は過密の言い方になるべき")
    }

    let thirteenTen = RunStatusLogic.nowReading(now: at(hour: 13, minute: 10), range: range, bands: bands)
    if case .ridingNormal(remainingMinutes: 200, endsAt: let endsAt) = thirteenTen.caseKind {
      #expect(endsAt == at(hour: 16, minute: 30))
    } else {
      Issue.record("13:10 は平常運転の言い方になるべき")
    }

    let seventeen = RunStatusLogic.nowReading(now: at(hour: 17), range: range, bands: bands)
    if case .afterLastNormal(status: .hold) = seventeen.caseKind {
      #expect(seventeen.referencedNormalBand == nil)
    } else {
      Issue.record("17:00 は本日の平常運転は終了になるべき")
    }

    let nineteenTen = RunStatusLogic.nowReading(now: at(hour: 19, minute: 10), range: range, bands: bands)
    if case .afterRangeEnd = nineteenTen.caseKind {
    } else {
      Issue.record("19:10 は本日の運転終了になるべき")
    }
  }

  @Test func nowReading_packedMorningExample() {
    let range = TimetableRangeLogic.compute(
      scheduledBlocks: packedScheduled,
      referenceDay: dayStart,
      calendar: utc
    )
    let bands = RunStatusLogic.bands(range: range, adoptedBlocks: packedAdopted)
    #expect(bands.count == 3)
    #expect(bands[0].kind == .dense)
    #expect(bands[1].kind == .hold)
    #expect(bands[1].startsAt == at(hour: 9) && bands[1].endsAt == at(hour: 10, minute: 20))
    #expect(bands[2].kind == .normal)
    #expect(bands[2].startsAt == at(hour: 10, minute: 20) && bands[2].endsAt == at(hour: 12))

    let nineThirty = RunStatusLogic.nowReading(now: at(hour: 9, minute: 30), range: range, bands: bands)
    if case .waitingForNormal(status: .hold, minutesUntilNextNormal: 50, nextNormalDurationMinutes: 100) =
      nineThirty.caseKind
    {
      #expect(nineThirty.referencedNormalBand?.startsAt == at(hour: 10, minute: 20))
    } else {
      Issue.record("09:30 は見合わせの言い方になるべき")
    }
  }

  @Test func nextMarkers_adoptedOnlyAndOverlap() {
    let blocks = stdAdopted
    let outside = RunStatusLogic.nextMarkers(now: at(hour: 9, minute: 50), adoptedBlocks: blocks)
    #expect(outside.nextStopInTarget == at(hour: 10))
    #expect(outside.nextRideInTarget == nil)

    let inside = RunStatusLogic.nextMarkers(now: at(hour: 10, minute: 5), adoptedBlocks: blocks)
    #expect(inside.nextRideInTarget == at(hour: 11))
    #expect(inside.nextStopInTarget == nil)
    #expect(inside.currentBandEndsAt == at(hour: 11))
  }

  @Test func serviceLoad_subtractsAdoptedOverlap() {
    let range = TimetableRangeLogic.compute(
      scheduledBlocks: stdScheduled,
      referenceDay: dayStart,
      calendar: utc
    )
    let load = ServiceLoadLogic.compute(
      now: at(hour: 11),
      range: range,
      adoptedBlocks: stdAdopted,
      ticketsAboveCutoff: [
        ServiceLoadTicket(durationMinutes: 45),
        ServiceLoadTicket(durationMinutes: 30),
      ]
    )
    #expect(load.freeMinutes == 6 * 60)
    #expect(load.ticketMinutes == 75)
    #expect(load.fitsWithinFree)
    #expect(load.overflowMinutes == 0)
  }

  @Test func runStatusFormat_matchesSpecExamples() {
    #expect(RunStatusLogic.formatHM(150) == "2:30")
    #expect(RunStatusLogic.formatHM(70) == "1:10")
    #expect(RunStatusLogic.formatHM(200) == "3:20")
    #expect(RunStatusLogic.formatHM(330) == "5:30")
    #expect(RunStatusLogic.formatHM(50) == "0:50")
    #expect(RunStatusLogic.formatHM(100) == "1:40")
  }
}