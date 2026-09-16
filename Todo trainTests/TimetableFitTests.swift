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
        #expect(
            TimetableFit.occupancyLines(fit: snap, now: now, calendar: utc) == [
                "いま 22:23 10分 週次",
                "次 22:33 20分 1on1"
            ]
        )
        let rows = TimetableFit.occupancyRows(fit: snap, now: now, calendar: utc)
        #expect(rows.map(\.kind) == [.occupying, .next])
        #expect(rows.map(\.clock) == ["22:23", "22:33"])
        #expect(rows.map(\.remainingMinutes) == [10, 20])
        let marks = TimetableFit.occupancyMarks(fit: snap, now: now)
        #expect(marks.count == 2)
        #expect(marks[0].isCurrent)
        #expect(abs(marks[0].span - (10.0 / 60.0)) < 0.0001)
        #expect(abs(marks[1].position - (20.0 / 60.0)) < 0.0001)
        let onProgress = TimetableFit.occupancyOnProgress(
            fit: snap,
            now: now,
            elapsed: 5 * 60,
            budget: 30 * 60
        )
        #expect(abs((onProgress.spanStart ?? -1) - (5.0 / 30.0)) < 0.0001)
        #expect(abs((onProgress.spanEnd ?? -1) - (15.0 / 30.0)) < 0.0001)
        #expect(abs((onProgress.mark ?? -1) - (25.0 / 30.0)) < 0.0001)
        let pastRide = TimetableFit.occupancyOnProgress(
            fit: snap,
            now: now,
            elapsed: 25 * 60,
            budget: 30 * 60
        )
        #expect(pastRide.mark == nil)
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
        #expect(TimetableFit.dutyLine(fit: snap, now: now, calendar: utc) == "掲示 22:28 15分 定例")
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

    @Test func boardingDispatch_zoomsWhenOccupancyIsInArrivalWindow() {
        let near = TimetableFitBlock(
            title: "タスク",
            startsAt: now.addingTimeInterval(14 * 60),
            endsAt: now.addingTimeInterval(44 * 60)
        )
        let fit = TimetableFit.snapshot(blocks: [near], now: now, budgetEndsAt: nil)
        let scheduled = now.addingTimeInterval(10 * 60)
        let predicted = now.addingTimeInterval(12 * 60)
        let dispatch = TimetableFit.boardingDispatch(
            fit: fit,
            now: now,
            scheduledArrival: scheduled,
            predictedArrival: predicted
        )
        #expect(dispatch.zooms)
        #expect(dispatch.occupancyEdge == near.startsAt)
        #expect(dispatch.windowSeconds < TimeInterval(TimetableFit.markWindowMinutes * 60))
        let fill = TimetableFit.dispatchFraction(offset: 10 * 60, windowSeconds: dispatch.windowSeconds)
        let chip = TimetableFit.dispatchFraction(offset: 14 * 60, windowSeconds: dispatch.windowSeconds)
        #expect((fill ?? 1) < (chip ?? 0))
    }

    @Test func boardingDispatch_staysQuietWhenOccupancyIsFar() {
        let far = TimetableFitBlock(
            title: "夕方",
            startsAt: now.addingTimeInterval(50 * 60),
            endsAt: now.addingTimeInterval(80 * 60)
        )
        let fit = TimetableFit.snapshot(blocks: [far], now: now, budgetEndsAt: nil)
        let dispatch = TimetableFit.boardingDispatch(
            fit: fit,
            now: now,
            scheduledArrival: now.addingTimeInterval(10 * 60),
            predictedArrival: now.addingTimeInterval(12 * 60)
        )
        #expect(!dispatch.zooms)
        #expect(dispatch.windowSeconds == TimeInterval(TimetableFit.markWindowMinutes * 60))
    }

    @Test func boardingDispatch_zoomsWhileOccupyingNow() {
        let current = TimetableFitBlock(
            title: "定例",
            startsAt: now.addingTimeInterval(-60),
            endsAt: now.addingTimeInterval(15 * 60)
        )
        let fit = TimetableFit.snapshot(
            blocks: [],
            notices: [current],
            now: now,
            budgetEndsAt: nil
        )
        let dispatch = TimetableFit.boardingDispatch(
            fit: fit,
            now: now,
            scheduledArrival: now.addingTimeInterval(30 * 60),
            predictedArrival: nil
        )
        #expect(dispatch.zooms)
        #expect(dispatch.occupancyEdge == current.endsAt)
    }

    @Test func rideDispatch_magnifiesRemainingRace() {
        let occupancy = TimetableProgressOccupancy(spanStart: nil, spanEnd: nil, mark: 0.4)
        let zoomed = TimetableFit.rideDispatch(occupancy: occupancy, progress: 0.1)
        #expect(zoomed.zooms)
        #expect(abs(zoomed.progress - 0.25) < 0.0001)
        #expect(abs((zoomed.occupancy.mark ?? -1) - 1) < 0.0001)
        let quiet = TimetableFit.rideDispatch(
            occupancy: TimetableProgressOccupancy(spanStart: nil, spanEnd: nil, mark: 0.96),
            progress: 0.2
        )
        #expect(!quiet.zooms)
        #expect(quiet.progress == 0.2)
    }
}
