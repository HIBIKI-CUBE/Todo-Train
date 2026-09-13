//
//  CheckInSchedulingTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct CheckInSchedulingTests {
    private let seed = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func progressCount_shortTripHasNone() {
        #expect(CheckInScheduling.progressCount(estimatedSeconds: 5 * 60) == 0)
        #expect(CheckInScheduling.progressCount(estimatedSeconds: 10 * 60) == 0)
        #expect(CheckInScheduling.offsets(estimatedSeconds: 600, seed: seed).isEmpty)
    }

    @Test func progressCount_mediumHasOne() {
        #expect(CheckInScheduling.progressCount(estimatedSeconds: 11 * 60) == 1)
        #expect(CheckInScheduling.progressCount(estimatedSeconds: 15 * 60) == 1)
        #expect(CheckInScheduling.progressCount(estimatedSeconds: 25 * 60) == 1)
        #expect(CheckInScheduling.offsets(estimatedSeconds: 20 * 60, seed: seed).count == 1)
    }

    @Test func progressCount_longHasTwo() {
        #expect(CheckInScheduling.progressCount(estimatedSeconds: 30 * 60) == 2)
        #expect(CheckInScheduling.progressCount(estimatedSeconds: 60 * 60) == 2)
        #expect(CheckInScheduling.offsets(estimatedSeconds: 30 * 60, seed: seed).count == 2)
    }

    @Test func offsets_lieInsideBands_andAreStableForSeed() {
        let first = CheckInScheduling.offsets(estimatedSeconds: 1800, seed: seed)
        let again = CheckInScheduling.offsets(estimatedSeconds: 1800, seed: seed)
        #expect(first == again)
        #expect(first.count == 2)

        let other = CheckInScheduling.offsets(
            estimatedSeconds: 1800,
            seed: UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        #expect(first != other)

        let budget = 1800.0
        #expect(first[0] >= budget * CheckInScheduling.firstBand.lowerBound)
        #expect(first[0] <= budget * CheckInScheduling.firstBand.upperBound)
        #expect(first[1] >= budget * CheckInScheduling.secondBand.lowerBound)
        #expect(first[1] <= budget * CheckInScheduling.secondBand.upperBound)
        #expect(first[0] < first[1])
    }

    @Test func unit_isStableAndInUnitInterval() {
        let a = CheckInScheduling.unit(seed: seed, salt: 1)
        let b = CheckInScheduling.unit(seed: seed, salt: 1)
        let c = CheckInScheduling.unit(seed: seed, salt: 2)
        #expect(a == b)
        #expect(a != c)
        #expect(a >= 0 && a < 1)
    }

    @Test func dueProgressOffset_nilUntilElapsed() {
        let offsets = [400.0, 800.0]
        #expect(
            CheckInScheduling.dueProgressOffset(
                offsets: offsets,
                firedCount: 0,
                elapsedSeconds: 399,
                remainingSeconds: 1401,
                hasPending: false
            ) == nil
        )
        #expect(
            CheckInScheduling.dueProgressOffset(
                offsets: offsets,
                firedCount: 0,
                elapsedSeconds: 400,
                remainingSeconds: 1400,
                hasPending: false
            ) == 400
        )
    }

    @Test func dueProgressOffset_skipsWhenPendingOrOvertimeGuard() {
        let offsets = [400.0]
        #expect(
            CheckInScheduling.dueProgressOffset(
                offsets: offsets,
                firedCount: 0,
                elapsedSeconds: 400,
                remainingSeconds: 1400,
                hasPending: true
            ) == nil
        )
        #expect(
            CheckInScheduling.dueProgressOffset(
                offsets: offsets,
                firedCount: 0,
                elapsedSeconds: 400,
                remainingSeconds: 30,
                hasPending: false
            ) == nil
        )
        #expect(
            CheckInScheduling.dueProgressOffset(
                offsets: offsets,
                firedCount: 0,
                elapsedSeconds: 400,
                remainingSeconds: 0,
                hasPending: false
            ) == nil
        )
    }

    @Test func dueProgressOffset_secondOnlyAfterFirstFired() {
        let offsets = [400.0, 800.0]
        #expect(
            CheckInScheduling.dueProgressOffset(
                offsets: offsets,
                firedCount: 0,
                elapsedSeconds: 900,
                remainingSeconds: 900,
                hasPending: false
            ) == 400
        )
        #expect(
            CheckInScheduling.dueProgressOffset(
                offsets: offsets,
                firedCount: 1,
                elapsedSeconds: 900,
                remainingSeconds: 900,
                hasPending: false
            ) == 800
        )
        #expect(
            CheckInScheduling.dueProgressOffset(
                offsets: offsets,
                firedCount: 2,
                elapsedSeconds: 900,
                remainingSeconds: 900,
                hasPending: false
            ) == nil
        )
    }

    @Test func awayDelay_inRangeAndStable() {
        let delay = CheckInScheduling.awayDelay(seed: seed)
        #expect(delay >= 45 && delay <= 90)
        #expect(CheckInScheduling.awayDelay(seed: seed) == delay)
    }

    @Test func wallFireAt_nilWhenAlreadyDue() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            CheckInScheduling.wallFireAt(offset: 400, elapsedSeconds: 400, now: now) == nil
        )
        #expect(
            CheckInScheduling.wallFireAt(offset: 400, elapsedSeconds: 100, now: now)
                == now.addingTimeInterval(300)
        )
    }

    @Test func fallbackCopy_includesTitle() {
        #expect(CheckInCopy.fallback(title: "資料") == "まだ『資料』？")
        #expect(CheckInCopy.fallback(title: "  ") == "まだこれ？")
    }

    @Test func awayInterruptChannel_matchesSurfaces() {
        #expect(
            CheckInScheduling.awayInterruptChannel(
                cabinEnabled: false,
                alarmKitOwnsLiveActivity: false,
                sessionLiveActivityEnabled: true
            ) == .none
        )
        #expect(
            CheckInScheduling.awayInterruptChannel(
                cabinEnabled: true,
                alarmKitOwnsLiveActivity: true,
                sessionLiveActivityEnabled: true
            ) == .none
        )
        #expect(
            CheckInScheduling.awayInterruptChannel(
                cabinEnabled: true,
                alarmKitOwnsLiveActivity: false,
                sessionLiveActivityEnabled: true
            ) == .liveActivityAlert
        )
        #expect(
            CheckInScheduling.awayInterruptChannel(
                cabinEnabled: true,
                alarmKitOwnsLiveActivity: false,
                sessionLiveActivityEnabled: false
            ) == .localNotification
        )
    }
}
