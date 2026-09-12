import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Cabin broadcast scheduling")
struct CabinBroadcastSchedulingTests {
    private let seed = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func progressCountMatchesBands() {
        #expect(CabinBroadcastScheduling.progressCount(estimatedSeconds: 10 * 60) == 0)
        #expect(CabinBroadcastScheduling.progressCount(estimatedSeconds: 11 * 60) == 1)
        #expect(CabinBroadcastScheduling.progressCount(estimatedSeconds: 30 * 60) == 2)
    }

    @Test func offsetsAreStableAndInsideBands() {
        let first = CabinBroadcastScheduling.offsets(estimatedSeconds: 1800, seed: seed)
        let again = CabinBroadcastScheduling.offsets(estimatedSeconds: 1800, seed: seed)
        #expect(first == again)
        #expect(first.count == 2)
        let budget = 1800.0
        #expect(first[0] >= budget * CabinBroadcastScheduling.firstBand.lowerBound)
        #expect(first[0] <= budget * CabinBroadcastScheduling.firstBand.upperBound)
        #expect(first[1] >= budget * CabinBroadcastScheduling.secondBand.lowerBound)
        #expect(first[0] < first[1])
    }
}

@Suite("Cabin delivery")
struct CabinDeliveryTests {
    @Test func progressWithRideUsesPip() {
        #expect(CabinDelivery.surface(kind: .progress, hasRide: true) == .pip)
    }

    @Test func progressWithoutRideUsesNotification() {
        #expect(CabinDelivery.surface(kind: .progress, hasRide: false) == .notification)
    }

    @Test func idleUsesNotification() {
        #expect(CabinDelivery.surface(kind: .idle, hasRide: false) == .notification)
        #expect(CabinDelivery.surface(kind: .idle, hasRide: true) == .notification)
    }

    @Test func awayIsIgnored() {
        #expect(CabinDelivery.surface(kind: .away, hasRide: true) == .ignore)
    }

    @Test func unknownKindIsIgnored() {
        #expect(CabinDelivery.surface(kind: .unknown("future"), hasRide: true) == .ignore)
    }
}

@Suite("Cabin interrupt watch")
struct CabinInterruptWatchTests {
    let running: SnapPlaintext = {
        let data = try! ContractFixtures.data("fixtures/snap.json")
        return try! WireJSON.decoder().decode(SnapPlaintext.self, from: data)
    }()

    @Test func sameSeedMatchesOffsets() {
        let seed = running.sessionId!
        let offsets = CabinBroadcastScheduling.offsets(
            estimatedSeconds: running.estimatedSeconds!,
            seed: seed
        )
        #expect(!offsets.isEmpty)
    }

    @Test func pendingProgressIsDue() {
        var snap = running
        snap.pendingCabin = .progress
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_120,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(interrupt.isDue)
        #expect(interrupt.showsPip)
        #expect(interrupt.prompt == CabinCopy.prompt)
    }

    @Test func consumingFiredCountHidesNext() {
        var snap = running
        snap.pendingCabin = .progress
        snap.checkInFiredCount = 0
        let shown = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_120,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(shown.isDue)
        let after = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_120,
            localEnabled: true,
            optimisticFiredCount: 1
        )
        #expect(!after.isDue)
    }

    @Test func pauseIsNotProgressDue() {
        var snap = running
        snap.phase = .paused
        snap.pausedAt = 1_768_000_100
        snap.pendingCabin = nil
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_200,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(!interrupt.isDue)
    }

    @Test func overtimeGuardSkipsLocalDue() {
        var snap = running
        snap.pendingCabin = nil
        snap.estimatedSeconds = 1500
        let nearEnd = 1_768_000_000 + 1480
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: nearEnd,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(!interrupt.isDue)
    }

    @Test func idleSchedulerDoesNotFireWithoutPending() {
        var snap = running
        snap.phase = .idle
        snap.sessionId = nil
        snap.serviceActive = true
        snap.pendingCabin = nil
        #expect(!CabinInterruptWatch.isIdleSchedulerDue(serviceActive: true, pendingCabin: nil))
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_120,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(!interrupt.isDue)
    }

    @Test func idlePendingIsDueForNotificationOnly() {
        var snap = running
        snap.phase = .idle
        snap.sessionId = nil
        snap.serviceActive = true
        snap.pendingCabin = .idle
        #expect(CabinInterruptWatch.isIdleSchedulerDue(serviceActive: true, pendingCabin: .idle))
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_120,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(interrupt.isDue)
        #expect(interrupt.delivery == .notification)
        #expect(!interrupt.showsPip)
    }

    @Test func localDisabledHides() {
        var snap = running
        snap.pendingCabin = .progress
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_120,
            localEnabled: false,
            optimisticFiredCount: 0
        )
        #expect(!interrupt.isDue)
    }

    @Test func snapCabinDisabledHides() {
        var snap = running
        snap.pendingCabin = .progress
        snap.cabinEnabled = false
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_120,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(!interrupt.isDue)
    }

    @Test func unknownPendingIsIgnoredForDisplay() {
        var snap = running
        snap.pendingCabin = .unknown("future")
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: 1_768_000_120,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(!interrupt.isDue)
        #expect(interrupt.prompt == nil)
    }

    @Test func elapsedDueWithoutPendingShowsPip() {
        var snap = running
        snap.pendingCabin = nil
        snap.checkInFiredCount = 0
        let offsets = CabinBroadcastScheduling.offsets(
            estimatedSeconds: snap.estimatedSeconds!,
            seed: snap.sessionId!
        )
        let fireAt = 1_768_000_000 + Int(offsets[0].rounded(.towardZero)) + 1
        let interrupt = CabinInterruptWatch.evaluate(
            snap: snap,
            now: fireAt,
            localEnabled: true,
            optimisticFiredCount: 0
        )
        #expect(interrupt.isDue)
        #expect(interrupt.showsPip)
    }
}
