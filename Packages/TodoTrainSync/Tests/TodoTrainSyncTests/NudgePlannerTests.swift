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

    @Test func anUnextendedCheckInStaysCurrentAfterItHasPassed() {
        // 15 min: stage 1 is at most 702s, approach is at 747s.
        let now = start.addingTimeInterval(720)
        let evaluation = NudgePlanner.evaluate(
            rideInput(estimatedSeconds: 15 * 60, rideID: ride, startedAt: start, now: now)
        )
        #expect(evaluation.current == .checkIn)
        #expect(!evaluation.plan.contains { $0.stage == .checkIn })
    }

    @Test func extensionAfterCheckInDoesNotRunItAgain() {
        // 15 min stage 1 is at most 702s. At 1000s it has fired.
        // 30 min stage 1 is at least 1116s, so a re-place would still be ahead.
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

    @Test func extensionBeforeCheckInReplacesItOnTheNewEstimate() throws {
        // 20 min stage 1 is at least 744s. At 60s it has not fired.
        // 40 min stage 1 is at least 1488s, so the new point is still ahead.
        let elapsed: TimeInterval = 60
        let now = start.addingTimeInterval(elapsed)
        let extendedEstimate = 40 * 60
        let placed = try #require(NudgePlanner.checkInOffset(estimatedSeconds: extendedEstimate, rideID: ride))
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: extendedEstimate,
                rideID: ride,
                startedAt: start,
                extensions: [NudgeExtension(addedSeconds: 20 * 60, createdAt: now)],
                now: now
            )
        )
        let checkIns = evaluation.plan.filter { $0.stage == .checkIn }
        #expect(checkIns.count == 1)
        #expect(checkIns.first?.fireAt == now.addingTimeInterval(placed - elapsed))
        #expect(checkIns.first?.rings == false)
        #expect(evaluation.current != .checkIn)
        #expect(evaluation.plan.filter(\.rings).count == 4)
        let remaining = NudgePlanner.approachRemaining(estimatedSeconds: extendedEstimate)
        let approach = evaluation.plan.first { $0.stage == .approach }
        #expect(approach?.fireAt == now.addingTimeInterval((Double(extendedEstimate) - remaining) - elapsed))

        let table = NudgePlanner.marks(
            estimatedSeconds: extendedEstimate,
            rideID: ride,
            extensions: [NudgeExtension(addedSeconds: 20 * 60, createdAt: now)],
            startedAt: start,
            activeSeconds: elapsed
        )
        #expect(table.first { $0.stage == .checkIn }?.offset == placed)
    }

    @Test func replacedCheckInAlreadyPassedIsSkipped() {
        // 8 min has no stage 1. 12 min stage 1 is at most 561.6s, and 11 min is past it.
        // Approach for 12 min is also behind 11 min, so the next plan entry is the estimate.
        let now = start.addingTimeInterval(11 * 60)
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 12 * 60,
                rideID: ride,
                startedAt: start,
                extensions: [NudgeExtension(addedSeconds: 4 * 60, createdAt: now)],
                now: now
            )
        )
        #expect(!evaluation.plan.contains { $0.stage == .checkIn })
        #expect(evaluation.current != .checkIn)
        #expect(evaluation.plan.first?.stage == .estimate)
        #expect(evaluation.plan.allSatisfy { $0.stage != .checkIn })
    }

    @Test func replacedCheckInAtTheActiveSecondIsSkipped() throws {
        let extendedEstimate = 40 * 60
        let placed = try #require(NudgePlanner.checkInOffset(estimatedSeconds: extendedEstimate, rideID: ride))
        let extensionAt = start.addingTimeInterval(60)
        let atPoint = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: extendedEstimate,
                rideID: ride,
                startedAt: start,
                extensions: [NudgeExtension(addedSeconds: 20 * 60, createdAt: extensionAt)],
                now: start.addingTimeInterval(placed)
            )
        )
        #expect(!atPoint.plan.contains { $0.stage == .checkIn })
        #expect(atPoint.current != .checkIn)

        let justBefore = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: extendedEstimate,
                rideID: ride,
                startedAt: start,
                extensions: [NudgeExtension(addedSeconds: 20 * 60, createdAt: extensionAt)],
                now: start.addingTimeInterval(placed - 1)
            )
        )
        let checkIn = try #require(justBefore.plan.first { $0.stage == .checkIn })
        #expect(checkIn.fireAt == start.addingTimeInterval(placed))
        #expect(justBefore.current != .checkIn)
    }

    @Test func tenMinuteEstimateStillHasNoCheckInAfterExtension() throws {
        let now = start.addingTimeInterval(30)
        let atTen = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 10 * 60,
                rideID: ride,
                startedAt: start,
                extensions: [NudgeExtension(addedSeconds: 5 * 60, createdAt: now)],
                now: now
            )
        )
        #expect(!atTen.plan.contains { $0.stage == .checkIn })
        #expect(atTen.current != .checkIn)

        // 601s stage 1 is at least 372s, so at 30s the new point is ahead.
        let justOverEstimate = 10 * 60 + 1
        let placed = try #require(NudgePlanner.checkInOffset(estimatedSeconds: justOverEstimate, rideID: ride))
        let justOver = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: justOverEstimate,
                rideID: ride,
                startedAt: start,
                extensions: [NudgeExtension(addedSeconds: 5 * 60 + 1, createdAt: now)],
                now: now
            )
        )
        let checkIn = try #require(justOver.plan.first { $0.stage == .checkIn })
        #expect(checkIn.fireAt == now.addingTimeInterval(placed - 30))
    }

    @Test func secondExtensionAfterTheReplacedCheckInDoesNotRunItAgain() {
        // After the first extension the estimate is 30 min, so stage 1 is at most 1404s.
        // The second extension is at 1404s. 40 min stage 1 is at least 1488s, so it would still be ahead.
        let firstAt = start.addingTimeInterval(100)
        let secondAt = start.addingTimeInterval(1_404)
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 40 * 60,
                rideID: ride,
                startedAt: start,
                extensions: [
                    NudgeExtension(addedSeconds: 10 * 60, createdAt: firstAt),
                    NudgeExtension(addedSeconds: 10 * 60, createdAt: secondAt),
                ],
                now: secondAt
            )
        )
        #expect(!evaluation.plan.contains { $0.stage == .checkIn })
        #expect(evaluation.current != .checkIn)
    }

    @Test func twoExtensionsBeforeCheckInPlaceItOnceOnTheFinalEstimate() throws {
        // Both stamps are before 20 min stage 1 (at least 744s) and before 30 min stage 1 (at least 1116s).
        let firstAt = start.addingTimeInterval(60)
        let secondAt = start.addingTimeInterval(120)
        let finalEstimate = 40 * 60
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: finalEstimate,
                rideID: ride,
                startedAt: start,
                extensions: [
                    NudgeExtension(addedSeconds: 10 * 60, createdAt: secondAt),
                    NudgeExtension(addedSeconds: 10 * 60, createdAt: firstAt),
                ],
                now: secondAt
            )
        )
        let checkIns = evaluation.plan.filter { $0.stage == .checkIn }
        #expect(checkIns.count == 1)
        let placed = try #require(NudgePlanner.checkInOffset(estimatedSeconds: finalEstimate, rideID: ride))
        #expect(checkIns.first?.fireAt == secondAt.addingTimeInterval(placed - 120))
    }

    @Test func extensionUsesActiveSecondsRatherThanWallClock() throws {
        // Wall clock is 1000s, but 800s were paused, so active seconds are 200.
        // 15 min stage 1 is at least 558s, so it has not fired. 30 min stage 1 is still ahead of 200s.
        let now = start.addingTimeInterval(1_000)
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 30 * 60,
                rideID: ride,
                startedAt: start,
                pausedAccumulated: 800,
                extensions: [NudgeExtension(addedSeconds: 15 * 60, createdAt: now)],
                now: now
            )
        )
        #expect(evaluation.workingElapsed == 200)
        let placed = try #require(NudgePlanner.checkInOffset(estimatedSeconds: 30 * 60, rideID: ride))
        let checkIn = try #require(evaluation.plan.first { $0.stage == .checkIn })
        #expect(checkIn.fireAt == now.addingTimeInterval(placed - 200))
    }

    @Test func openPauseAfterExtensionDoesNotCountAsFired() throws {
        let extensionAt = start.addingTimeInterval(100)
        let pausedAt = start.addingTimeInterval(500)
        let now = start.addingTimeInterval(800)
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 40 * 60,
                rideID: ride,
                startedAt: start,
                pausedAt: pausedAt,
                isPaused: true,
                extensions: [NudgeExtension(addedSeconds: 20 * 60, createdAt: extensionAt)],
                now: now
            )
        )
        #expect(evaluation.workingElapsed == 500)
        #expect(evaluation.isFrozen)
        let placed = try #require(NudgePlanner.checkInOffset(estimatedSeconds: 40 * 60, rideID: ride))
        let checkIn = try #require(evaluation.plan.first { $0.stage == .checkIn })
        #expect(checkIn.fireAt == now.addingTimeInterval(placed - 500))
    }

    @Test func openPassengerIntervalAfterExtensionDoesNotCountAsFired() throws {
        let extensionAt = start.addingTimeInterval(100)
        let passengerSince = start.addingTimeInterval(500)
        let now = start.addingTimeInterval(800)
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 40 * 60,
                rideID: ride,
                startedAt: start,
                passengerSince: passengerSince,
                isPassenger: true,
                extensions: [NudgeExtension(addedSeconds: 20 * 60, createdAt: extensionAt)],
                now: now
            )
        )
        #expect(evaluation.workingElapsed == 500)
        #expect(evaluation.isFrozen)
        let placed = try #require(NudgePlanner.checkInOffset(estimatedSeconds: 40 * 60, rideID: ride))
        let checkIn = try #require(evaluation.plan.first { $0.stage == .checkIn })
        #expect(checkIn.fireAt == now.addingTimeInterval(placed - 500))
    }

    @Test func recordedWorkingSecondsKeepAFiredCheckInFromReturning() {
        // The extension was at 800 active seconds, after 15 min stage 1 (at most 702s).
        // A later 400s pause would make a derived reading look earlier than that point.
        // 30 min stage 1 is at least 1116s, and live active seconds are 810, so it would still be ahead.
        let extensionAt = start.addingTimeInterval(800)
        let now = start.addingTimeInterval(1_210)
        let evaluation = NudgePlanner.evaluate(
            rideInput(
                estimatedSeconds: 30 * 60,
                rideID: ride,
                startedAt: start,
                pausedAccumulated: 400,
                extensions: [
                    NudgeExtension(addedSeconds: 15 * 60, createdAt: extensionAt, workingSeconds: 800),
                ],
                now: now
            )
        )
        #expect(evaluation.workingElapsed == 810)
        #expect(!evaluation.plan.contains { $0.stage == .checkIn })
        #expect(evaluation.current != .checkIn)
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
