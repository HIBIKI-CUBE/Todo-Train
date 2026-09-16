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
        #expect(snap.markMinutes == 20)
        #expect(snap.nextDeadline == next.startsAt)
        #expect(snap.remainingMinutes == 10)
        #expect(snap.shouldSuppressAway)
        #expect(snap.visibleBlock?.title == "週次")
        #expect(TimetableFit.occupyingLine(title: "週次", remainingMinutes: 10) == "いま 週次 10分")
        #expect(TimetableFit.nextBlockLine(title: "週次", startsAt: current.startsAt, now: now) == "週次")
        #expect(TimetableFit.nextBlockLine(title: "1on1", startsAt: next.startsAt, now: now) == "次 1on1 20分")
        #expect(
            TimetableFit.dutyLine(fit: snap, now: now) == "いま 週次 10分"
        )
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

    @Test func dutyLine_noticeWhenNoAdoptedOccupancy() {
        let next = TimetableFitBlock(
            title: "1on1",
            startsAt: now.addingTimeInterval(20 * 60),
            endsAt: now.addingTimeInterval(50 * 60)
        )
        let snap = TimetableFit.snapshot(blocks: [next], now: now, budgetEndsAt: nil)
        #expect(
            TimetableFit.dutyLine(
                fit: snap,
                noticeTitle: "定例",
                noticeEndsAt: now.addingTimeInterval(15 * 60),
                now: now
            ) == "掲示 定例 15分"
        )
        #expect(TimetableFit.dutyLine(fit: snap, now: now) == "次 1on1 20分")
    }
}
