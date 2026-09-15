//
//  TimetableBoardingOverlapTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TimetableBoardingOverlapTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func interval(
        _ title: String,
        from: TimeInterval,
        duration: TimeInterval = 1800
    ) -> TimetableBoardInterval {
        TimetableBoardInterval(
            title: title,
            startsAt: now.addingTimeInterval(from),
            endsAt: now.addingTimeInterval(from + duration)
        )
    }

    @Test func adoptedNow_beatsSoonAndNotice() {
        let conflict = TimetableBoardingOverlap.conflict(
            now: now,
            rideEnd: now.addingTimeInterval(1800),
            adopted: [
                interval("週次", from: -300),
                interval("1on1", from: 600)
            ],
            notices: [interval("掲示会議", from: -60)]
        )
        #expect(conflict == .adoptedNow(title: "週次"))
    }

    @Test func adoptedSoon_whenEstimateOverlaps() {
        let conflict = TimetableBoardingOverlap.conflict(
            now: now,
            rideEnd: now.addingTimeInterval(1800),
            adopted: [interval("1on1", from: 600)],
            notices: []
        )
        #expect(conflict == .adoptedSoon(title: "1on1"))
    }

    @Test func adoptedSoon_ignoredWhenEstimateEndsFirst() {
        let conflict = TimetableBoardingOverlap.conflict(
            now: now,
            rideEnd: now.addingTimeInterval(300),
            adopted: [interval("1on1", from: 600)],
            notices: []
        )
        #expect(conflict == nil)
    }

    @Test func noticeNow_onlyWhenNotAdopted() {
        let conflict = TimetableBoardingOverlap.conflict(
            now: now,
            rideEnd: now.addingTimeInterval(1800),
            adopted: [],
            notices: [interval("定例", from: -60)]
        )
        #expect(conflict == .noticeNow(title: "定例"))
    }

    @Test func futureNotice_doesNotWarn() {
        let conflict = TimetableBoardingOverlap.conflict(
            now: now,
            rideEnd: now.addingTimeInterval(1800),
            adopted: [],
            notices: [interval("定例", from: 600)]
        )
        #expect(conflict == nil)
    }
}
