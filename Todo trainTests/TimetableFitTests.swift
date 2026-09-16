//
//  TimetableFitTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

@MainActor
struct TimetableFitTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func markMinutes_floorsAndCaps() {
        #expect(TimetableFit.markMinutes(until: now.addingTimeInterval(20 * 60), now: now) == 20)
        #expect(TimetableFit.markMinutes(until: now.addingTimeInterval(60 * 60), now: now) == 60)
        #expect(TimetableFit.markMinutes(until: now.addingTimeInterval(61 * 60), now: now) == nil)
        #expect(TimetableFit.markMinutes(until: now.addingTimeInterval(30), now: now) == nil)
        #expect(TimetableFit.markMinutes(until: now.addingTimeInterval(59), now: now) == nil)
        #expect(TimetableFit.markMinutes(until: now.addingTimeInterval(60), now: now) == 1)
        #expect(TimetableFit.markMinutes(until: now.addingTimeInterval(20 * 60 + 59), now: now) == 20)
    }

    @Test func snapshot_picksCurrentAndNext() {
        let current = TimetableFitBlock(
            title: "週次",
            startsAt: now.addingTimeInterval(-600),
            endsAt: now.addingTimeInterval(600)
        )
        let next = TimetableFitBlock(
            title: "1on1",
            startsAt: now.addingTimeInterval(20 * 60),
            endsAt: now.addingTimeInterval(50 * 60)
        )
        let budgetEnd = now.addingTimeInterval(1800)
        let snap = TimetableFit.snapshot(blocks: [next, current], now: now, budgetEndsAt: budgetEnd)
        #expect(snap.currentBlock?.title == "週次")
        #expect(snap.nextBlock?.title == "1on1")
        #expect(snap.currentOccupancy?.title == "週次")
        #expect(snap.currentOccupancy?.isAdopted == true)
        #expect(snap.nextOccupancy?.title == "1on1")
        #expect(snap.markMinutes == 20)
        #expect(snap.nextDeadline == next.startsAt)
        #expect(snap.remainingMinutes == 10)
        #expect(snap.shouldSuppressAway)
        #expect(snap.visibleBlock?.title == "週次")
        #expect(snap.visibleOccupancy?.title == "週次")
        #expect(TimetableFit.occupyingLine(
            title: "週次",
            endsAt: current.endsAt,
            now: now,
            calendar: utc
        ) == "いま 22:23 10分 週次")
        #expect(TimetableFit.nextBlockLine(title: "週次", startsAt: current.startsAt, now: now) == "週次")
        #expect(TimetableFit.nextBlockLine(
            title: "1on1",
            startsAt: next.startsAt,
            now: now,
            calendar: utc
        ) == "次 22:33 20分 1on1")
        #expect(TimetableFit.dutyLine(fit: snap, now: now, calendar: utc) == "いま 22:23 10分 週次")
        #expect(TimetableFit.nextDutyLine(fit: snap, now: now, calendar: utc) == "次 22:33 20分 1on1")
        #expect(TimetableFit.occupancyLines(fit: snap, now: now, calendar: utc) == [
            "いま 22:23 10分 週次",
            "次 22:33 20分 1on1"
        ])
    }

    @Test func snapshot_budgetWinsWhenEarlierThanBlock() {
        let next = TimetableFitBlock(
            title: "会議",
            startsAt: now.addingTimeInterval(40 * 60),
            endsAt: now.addingTimeInterval(70 * 60)
        )
        let budgetEnd = now.addingTimeInterval(10 * 60)
        let snap = TimetableFit.snapshot(blocks: [next], now: now, budgetEndsAt: budgetEnd)
        #expect(snap.nextDeadline == budgetEnd)
        #expect(snap.markMinutes == 40)
        #expect(snap.shouldSuppressAway == false)
    }

    @Test func snapshot_suppressesAwayTwoMinutesBefore() {
        let block = TimetableFitBlock(
            title: "会議",
            startsAt: now.addingTimeInterval(90),
            endsAt: now.addingTimeInterval(30 * 60)
        )
        let snap = TimetableFit.snapshot(blocks: [block], now: now, budgetEndsAt: nil)
        #expect(snap.shouldSuppressAway)
        let far = TimetableFit.snapshot(
            blocks: [
                TimetableFitBlock(
                    title: "会議",
                    startsAt: now.addingTimeInterval(10 * 60),
                    endsAt: now.addingTimeInterval(40 * 60)
                )
            ],
            now: now,
            budgetEndsAt: nil
        )
        #expect(!far.shouldSuppressAway)
    }

    @Test func snapshot_suppressesAwayDuringUnadoptedNoticeOnly() {
        let notice = TimetableFitBlock(
            title: "定例",
            startsAt: now.addingTimeInterval(-60),
            endsAt: now.addingTimeInterval(1800)
        )
        let overlapping = TimetableFit.snapshot(
            blocks: [],
            notices: [notice],
            now: now,
            budgetEndsAt: nil
        )
        #expect(overlapping.shouldSuppressAway)
        let upcoming = TimetableFit.snapshot(
            blocks: [],
            notices: [
                TimetableFitBlock(
                    title: "定例",
                    startsAt: now.addingTimeInterval(10 * 60),
                    endsAt: now.addingTimeInterval(40 * 60)
                )
            ],
            now: now,
            budgetEndsAt: nil
        )
        #expect(!upcoming.shouldSuppressAway)
    }

    @Test func occupancy_noticeWhenNoAdoptedCurrent() {
        let next = TimetableFitBlock(
            title: "1on1",
            startsAt: now.addingTimeInterval(20 * 60),
            endsAt: now.addingTimeInterval(50 * 60)
        )
        let notice = TimetableFitBlock(
            title: "定例",
            startsAt: now.addingTimeInterval(-60),
            endsAt: now.addingTimeInterval(15 * 60)
        )
        let snap = TimetableFit.snapshot(
            blocks: [next],
            notices: [notice],
            now: now,
            budgetEndsAt: nil
        )
        #expect(snap.currentOccupancy?.title == "定例")
        #expect(snap.currentOccupancy?.isAdopted == false)
        #expect(snap.nextOccupancy?.title == "1on1")
        #expect(TimetableFit.dutyLine(fit: snap, now: now, calendar: utc) == "掲示 22:27 15分 定例")
        #expect(TimetableFit.nextDutyLine(fit: snap, now: now, calendar: utc) == "次 22:33 20分 1on1")
        let adoptedOnly = TimetableFit.snapshot(blocks: [next], now: now, budgetEndsAt: nil)
        #expect(TimetableFit.dutyLine(fit: adoptedOnly, now: now, calendar: utc) == "次 22:33 20分 1on1")
        #expect(TimetableFit.nextDutyLine(fit: adoptedOnly, now: now) == nil)
    }

    @Test func occupancy_adoptedWinsOverOverlappingNotice() {
        let adopted = TimetableFitBlock(
            title: "週次",
            startsAt: now.addingTimeInterval(-600),
            endsAt: now.addingTimeInterval(600)
        )
        let notice = TimetableFitBlock(
            title: "定例",
            startsAt: now.addingTimeInterval(-120),
            endsAt: now.addingTimeInterval(1800)
        )
        let snap = TimetableFit.snapshot(
            blocks: [adopted],
            notices: [notice],
            now: now,
            budgetEndsAt: nil
        )
        #expect(snap.currentOccupancy?.title == "週次")
        #expect(snap.currentOccupancy?.isAdopted == true)
        #expect(snap.nextOccupancy == nil)
        #expect(TimetableFit.occupancyLines(fit: snap, now: now, calendar: utc) == ["いま 22:23 10分 週次"])
    }

    @Test func occupancy_nextPicksEarliestNoticeOrAdopted() {
        let adopted = TimetableFitBlock(
            title: "1on1",
            startsAt: now.addingTimeInterval(20 * 60),
            endsAt: now.addingTimeInterval(50 * 60)
        )
        let notice = TimetableFitBlock(
            title: "歯医者",
            startsAt: now.addingTimeInterval(10 * 60),
            endsAt: now.addingTimeInterval(40 * 60)
        )
        let snap = TimetableFit.snapshot(
            blocks: [adopted],
            notices: [notice],
            now: now,
            budgetEndsAt: nil
        )
        #expect(snap.currentOccupancy == nil)
        #expect(snap.nextOccupancy?.title == "歯医者")
        #expect(snap.nextOccupancy?.isAdopted == false)
        #expect(TimetableFit.occupancyLines(fit: snap, now: now, calendar: utc) == ["次 22:23 10分 歯医者"])
        #expect(snap.nextDeadline == adopted.startsAt)
    }

    @Test func noticeBlockID_isStable() {
        let first = TimetableFit.noticeBlockID("event|1700000000")
        let second = TimetableFit.noticeBlockID("event|1700000000")
        let other = TimetableFit.noticeBlockID("event|1700000001")
        #expect(first == second)
        #expect(first != other)
    }

    @Test func remainingMinutes_uncappedAndClockLeads() {
        #expect(TimetableFit.remainingMinutes(until: now.addingTimeInterval(90 * 60), now: now) == 90)
        #expect(TimetableFit.remainingMinutes(until: now.addingTimeInterval(20), now: now) == nil)
        #expect(TimetableFit.clockTime(now.addingTimeInterval(20 * 60), calendar: utc) == "22:33")
        let far = TimetableFitBlock(
            title: "夕方",
            startsAt: now.addingTimeInterval(90 * 60),
            endsAt: now.addingTimeInterval(120 * 60)
        )
        let snap = TimetableFit.snapshot(blocks: [far], now: now, budgetEndsAt: nil)
        #expect(snap.markMinutes == nil)
        #expect(
            TimetableFit.occupancyLines(fit: snap, now: now, calendar: utc) == ["次 23:43 90分 夕方"]
        )
    }
}
