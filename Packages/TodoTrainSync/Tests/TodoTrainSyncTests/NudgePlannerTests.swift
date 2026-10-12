import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Nudge stage table")
struct NudgeStageTableTests {
    @Test func fiveFifteenAndThirtyMinuteEstimatesMatchTheBands() {
        let five = 5 * 60
        let fifteen = 15 * 60
        let thirty = 30 * 60

        #expect(NudgePlanner.checkInBand(estimatedSeconds: five) == nil)
        #expect(NudgePlanner.approachRemaining(estimatedSeconds: five) == 60)
        #expect(NudgePlanner.handoffInterval(estimatedSeconds: five) == 60)

        let fifteenBand = NudgePlanner.checkInBand(estimatedSeconds: fifteen)
        #expect(fifteenBand?.lowerBound == TimeInterval(fifteen) * 0.62)
        #expect(fifteenBand?.upperBound == TimeInterval(fifteen) * 0.78)
        #expect(abs(NudgePlanner.approachRemaining(estimatedSeconds: fifteen) - 153) < 0.001)
        #expect(abs(NudgePlanner.handoffInterval(estimatedSeconds: fifteen) - 63) < 0.001)

        let thirtyBand = NudgePlanner.checkInBand(estimatedSeconds: thirty)
        #expect(thirtyBand?.lowerBound == TimeInterval(thirty) * 0.62)
        #expect(thirtyBand?.upperBound == TimeInterval(thirty) * 0.78)
        #expect(NudgePlanner.approachRemaining(estimatedSeconds: thirty) == 180)
        #expect(NudgePlanner.handoffInterval(estimatedSeconds: thirty) == 120)
    }

    @Test func stageMarksUseThoseThresholds() {
        let ride = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let marks = NudgePlanner.marks(estimatedSeconds: 30 * 60, rideID: ride)
        #expect(marks.map(\.stage) == [.checkIn, .approach, .estimate, .handoff1, .handoff2, .handoff3])
        let checkIn = marks[0].offset
        #expect(checkIn >= TimeInterval(30 * 60) * 0.62)
        #expect(checkIn <= TimeInterval(30 * 60) * 0.78)
        #expect(marks[1].offset == TimeInterval(30 * 60) - 180)
        #expect(marks[2].offset == TimeInterval(30 * 60))
        #expect(marks[3].offset == TimeInterval(30 * 60) + 120)
        #expect(marks[4].offset == TimeInterval(30 * 60) + 240)
        #expect(marks[5].offset == TimeInterval(30 * 60) + 360)
    }

    @Test func tenMinutesHasNoCheckIn() {
        #expect(NudgePlanner.checkInOffset(estimatedSeconds: 10 * 60, rideID: UUID()) == nil)
        #expect(NudgePlanner.checkInOffset(estimatedSeconds: 10 * 60 + 1, rideID: UUID()) != nil)
        let marks = NudgePlanner.marks(estimatedSeconds: 5 * 60, rideID: UUID())
        #expect(!marks.contains { $0.stage == .checkIn })
        #expect(marks.first?.stage == .approach)
    }
}

@Suite("Nudge check-in placement")
struct NudgeCheckInPlacementTests {
    @Test func sameRideKeepsOneOffset() {
        let ride = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = NudgePlanner.checkInOffset(estimatedSeconds: 15 * 60, rideID: ride)
        let again = NudgePlanner.checkInOffset(estimatedSeconds: 15 * 60, rideID: ride)
        #expect(first == again)
        let evaluation = NudgePlanner.evaluate(rideInput(estimatedSeconds: 15 * 60, rideID: ride))
        let repeated = NudgePlanner.evaluate(rideInput(estimatedSeconds: 15 * 60, rideID: ride))
        #expect(evaluation == repeated)
    }

    @Test func differentRidesSpreadInsideTheBand() {
        let estimate = 30 * 60
        let offsets = (0..<24).map { index in
            let ride = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index))!
            return NudgePlanner.checkInOffset(estimatedSeconds: estimate, rideID: ride)
        }
        let band = TimeInterval(estimate) * 0.62...TimeInterval(estimate) * 0.78
        #expect(offsets.allSatisfy { offset in
            guard let offset else { return false }
            return band.contains(offset)
        })
        #expect(Set(offsets).count > 1)
    }
}

@Suite("Nudge freeze and extension")
struct NudgeFreezeExtensionTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let ride = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func pauseHoldsTheStageAndResumeContinues() {
        let beforePause = NudgePlanner.evaluate(
            rideInput(estimatedSeconds: 5 * 60, rideID: ride, startedAt: start, now: start.addingTimeInterval(200))
        )
        #expect(beforePause.workingElapsed == 200)
        #expect(beforePause.current == nil)
        #expect(beforePause.plan.contains { $0.stage == .approach })

        let pausedAt = start.addingTimeInterval(200)
        let paused = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 5 * 60,
                rideID: ride,
                startedAt: start,
                pausedAt: pausedAt,
                isPaused: true,
                now: start.addingTimeInterval(1_200)
            )
        )
        #expect(paused.isFrozen)
        #expect(paused.workingElapsed == 200)
        #expect(paused.current == nil)
        #expect(paused.plan.contains { $0.stage == .approach })

        let resumed = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 5 * 60,
                rideID: ride,
                startedAt: start,
                pausedAccumulated: 1_000,
                now: start.addingTimeInterval(1_250)
            )
        )
        #expect(!resumed.isFrozen)
        #expect(resumed.workingElapsed == 250)
        #expect(resumed.current == .approach)
        #expect(!resumed.plan.contains { $0.stage == .approach })
        #expect(resumed.plan.contains { $0.stage == .estimate })
    }

    @Test func passengerHoldsTheStageAndReboardContinues() {
        let passengerSince = start.addingTimeInterval(200)
        let aboard = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 5 * 60,
                rideID: ride,
                startedAt: start,
                passengerSince: passengerSince,
                isPassenger: true,
                now: start.addingTimeInterval(1_200)
            )
        )
        #expect(aboard.isFrozen)
        #expect(aboard.workingElapsed == 200)
        #expect(aboard.current == nil)

        let reboarded = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 5 * 60,
                rideID: ride,
                startedAt: start,
                passengerAccumulated: 1_000,
                now: start.addingTimeInterval(1_250)
            )
        )
        #expect(reboarded.workingElapsed == 250)
        #expect(reboarded.current == .approach)
    }

    @Test func extensionRebuildsLaterStagesAndDropsCheckIn() {
        let elapsed = start.addingTimeInterval(1_000)
        let before = NudgePlanner.evaluate(
            rideInput(estimatedSeconds: 15 * 60, rideID: ride, startedAt: start, now: elapsed)
        )
        #expect(before.plan.contains { $0.stage == .checkIn } == false)
        #expect(before.plan.filter(\.rings).count < 4)

        let extended = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 30 * 60,
                rideID: ride,
                startedAt: start,
                extensions: [NudgeExtension(addedSeconds: 15 * 60, createdAt: elapsed)],
                now: elapsed
            )
        )
        #expect(!extended.plan.contains { $0.stage == .checkIn })
        #expect(extended.current != .checkIn)
        #expect(extended.plan.filter(\.rings).count == 4)
        let approach = extended.plan.first { $0.stage == .approach }
        #expect(approach?.fireAt == elapsed.addingTimeInterval((30 * 60 - 180) - 1_000))
        let estimate = extended.plan.first { $0.stage == .estimate }
        #expect(estimate?.fireAt == elapsed.addingTimeInterval((30 * 60) - 1_000))
        #expect(extended.plan.allSatisfy { $0.stage != .checkIn })
    }
}

@Suite("Nudge rings")
struct NudgeRingTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let ride = UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func twoForegroundDevicesAlternateFourRings() {
        let plan = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 30 * 60,
                rideID: ride,
                startedAt: start,
                foreground: [.iphone, .mac],
                macAttending: true,
                now: start
            )
        ).plan.filter(\.rings)
        #expect(plan.map(\.stage) == [.estimate, .handoff1, .handoff2, .handoff3])
        #expect(plan.map(\.surface) == [.mac, .iphone, .mac, .iphone])
        #expect(Set(plan.map(\.stage)).count == plan.count)
    }

    @Test func oneForegroundDeviceRingsOnStageThreeAndFive() {
        let iphone = ringing(
            foreground: [.iphone],
            macAttending: false
        )
        #expect(iphone.map(\.stage) == [.estimate, .handoff2])
        #expect(iphone.allSatisfy { $0.surface == .iphone })

        let mac = ringing(
            foreground: [.mac],
            macAttending: true
        )
        #expect(mac.map(\.stage) == [.estimate, .handoff2])
        #expect(mac.allSatisfy { $0.surface == .mac })
    }

    @Test func macNotAttendingStartsOnIPhone() {
        let plan = ringing(
            foreground: [.mac, .iphone],
            macAttending: false
        )
        #expect(plan.map(\.surface) == [.iphone, .mac, .iphone, .mac])
    }

    @Test func alarmBellOccupiesStageThreeAndMacEntersAtStageFour() throws {
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 30 * 60,
                rideID: ride,
                startedAt: start,
                alarmKitEndBell: true,
                foreground: [.mac, .iphone],
                macAttending: true,
                now: start
            )
        )
        let stage3 = try #require(evaluation.plan.first { $0.stage == .estimate })
        #expect(stage3.surface == NudgeSurface.none)
        #expect(stage3.rings == false)
        let ringing = evaluation.plan.filter(\.rings)
        #expect(ringing.map(\.stage) == [.handoff1, .handoff2, .handoff3])
        #expect(ringing.map(\.surface) == [.mac, .iphone, .mac])
        #expect(!ringing.contains { $0.surface == .mac && $0.stage == .estimate })
    }

    @Test func returnSkipsRingsThatAlreadyPassed() {
        // E=5min: stage 3 at 300, stage 4 at 360, stage 5 at 420.
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 5 * 60,
                rideID: ride,
                startedAt: start,
                foreground: [.mac, .iphone],
                macAttending: true,
                now: start.addingTimeInterval(400)
            )
        )
        #expect(evaluation.current == .handoff1)
        let stages = evaluation.plan.map(\.stage)
        #expect(!stages.contains(.estimate))
        #expect(!stages.contains(.handoff1))
        #expect(evaluation.plan.filter(\.rings).map(\.stage) == [.handoff2, .handoff3])
    }

    @Test func watchInTheForegroundArrayDoesNotJoinTheDefaultColumn() {
        let plan = ringing(
            foreground: [.mac, .iphone, .watch],
            macAttending: true
        )
        #expect(plan.map(\.surface) == [.mac, .iphone, .mac, .iphone])
    }

    @Test func deviceOrderCanIncludeWatch() {
        let plan = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 30 * 60,
                rideID: ride,
                startedAt: start,
                foreground: [.watch, .iphone, .mac],
                macAttending: true,
                now: start
            ),
            deviceOrder: [.mac, .iphone, .watch]
        ).plan.filter(\.rings)
        #expect(plan.map(\.surface) == [.mac, .iphone, .watch, .mac])
    }

    @Test func presenceWindowIsTwoMinutes() {
        #expect(NudgePlanner.macIsAttending(screenLocked: false, secondsSinceLastInput: 119))
        #expect(!NudgePlanner.macIsAttending(screenLocked: false, secondsSinceLastInput: 120))
        #expect(!NudgePlanner.macIsAttending(screenLocked: true, secondsSinceLastInput: 0))
    }

    private func ringing(foreground: [NudgeSurface], macAttending: Bool) -> [NudgePlanItem] {
        NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 30 * 60,
                rideID: ride,
                startedAt: start,
                foreground: foreground,
                macAttending: macAttending,
                now: start
            )
        ).plan.filter(\.rings)
    }
}

@Suite("Nudge arrival gaps")
struct NudgeGapTests {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func gapsStartAtTheStampAndStayDownWhileArrivalIsOpen() {
        let open = NudgePlanner.gaps(
            NudgeGapInput(
                stampedAt: stamp,
                arrivalScreenOpen: true,
                foreground: [.mac, .iphone],
                macAttending: true,
                now: stamp
            )
        )
        #expect(open.isEmpty)

        let closed = NudgePlanner.gaps(
            NudgeGapInput(
                stampedAt: stamp,
                arrivalScreenOpen: false,
                foreground: [.mac, .iphone],
                macAttending: true,
                now: stamp
            )
        )
        #expect(closed.map(\.stage) == [.gap1, .gap2])
        #expect(closed[0].fireAt == stamp.addingTimeInterval(3 * 60))
        #expect(closed[1].fireAt == stamp.addingTimeInterval(6 * 60))
        #expect(closed.map(\.surface) == [.mac, .iphone])
        #expect(closed.allSatisfy { $0.rings })
    }

    @Test func aPassedGapIsNotReturned() {
        let midway = NudgePlanner.gaps(
            NudgeGapInput(
                stampedAt: stamp,
                arrivalScreenOpen: false,
                foreground: [.mac, .iphone],
                macAttending: true,
                now: stamp.addingTimeInterval(3 * 60)
            )
        )
        #expect(midway.map(\.stage) == [.gap2])

        let finished = NudgePlanner.gaps(
            NudgeGapInput(
                stampedAt: stamp,
                arrivalScreenOpen: false,
                foreground: [.mac, .iphone],
                macAttending: true,
                now: stamp.addingTimeInterval(6 * 60)
            )
        )
        #expect(finished.isEmpty)
    }
}

private func rideInput(
    estimatedSeconds: Int,
    rideID: UUID,
    startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    pausedAccumulated: TimeInterval = 0,
    pausedAt: Date? = nil,
    isPaused: Bool = false,
    passengerAccumulated: TimeInterval = 0,
    passengerSince: Date? = nil,
    isPassenger: Bool = false,
    extensions: [NudgeExtension] = [],
    alarmKitEndBell: Bool = false,
    foreground: [NudgeSurface] = [.mac, .iphone],
    macAttending: Bool = true,
    now: Date? = nil
) -> NudgeRideInput {
    NudgeRideInput(
        startedAt: startedAt,
        pausedAccumulated: pausedAccumulated,
        pausedAt: pausedAt,
        isPaused: isPaused,
        passengerAccumulated: passengerAccumulated,
        passengerSince: passengerSince,
        isPassenger: isPassenger,
        estimatedSeconds: estimatedSeconds,
        rideID: rideID,
        extensions: extensions,
        alarmKitEndBell: alarmKitEndBell,
        foreground: foreground,
        macAttending: macAttending,
        now: now ?? startedAt
    )
}
