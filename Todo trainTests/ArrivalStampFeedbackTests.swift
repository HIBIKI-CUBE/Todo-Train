//
//  ArrivalStampFeedbackTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

@Suite("Arrival stamp feedback")
struct ArrivalStampFeedbackTests {
    @Test func onTimeDropsRoundStampThenCornerSeal() {
        let events = ArrivalStampFeedback.sequence(hasCornerSeal: true)
        let seal = StampFeedbackTiming.sealDelayMilliseconds
        let rigid = seal + StampFeedbackTiming.sealSecondHapticMilliseconds
        #expect(events.map(\.offsetMilliseconds) == [0, seal, rigid])
        #expect(events.map(\.sound) == [.roundStamp, .seal, nil])
        #expect(events.map(\.haptic) == [.roundLight, .sealHeavy, .sealRigid])
        #expect(events[1].offsetMilliseconds - events[0].offsetMilliseconds == seal)
        #expect(events[2].offsetMilliseconds - events[1].offsetMilliseconds == 70)
    }

    @Test func withoutCornerSealIsOnlyTheRoundStamp() {
        let events = ArrivalStampFeedback.sequence(hasCornerSeal: false)
        #expect(events == [
            ArrivalStampFeedback.Event(offsetMilliseconds: 0, sound: .roundStamp, haptic: .roundLight),
        ])
        #expect(events.allSatisfy { $0.sound != .seal })
        #expect(events.allSatisfy { $0.haptic != .sealHeavy && $0.haptic != .sealRigid })
    }

    @Test func sealDelayStaysInsideTheTuneRange() {
        let delay = StampFeedbackTiming.sealDelayMilliseconds
        #expect(delay >= 100)
        #expect(delay <= 200)
        #expect(delay <= 250)
        let events = ArrivalStampFeedback.sequence(hasCornerSeal: true)
        #expect(events[1].offsetMilliseconds == delay)
    }

    @Test func hapticIntensities() {
        #expect(ArrivalStampFeedback.roundLightIntensity == 0.6)
        #expect(ArrivalStampFeedback.sealHeavyIntensity == 1.0)
        #expect(ArrivalStampFeedback.sealRigidIntensity == 0.75)
        #expect(StampFeedbackTiming.sealSecondHapticMilliseconds == 70)
    }

    @Test func previewActiveTimeMatchesTheRequestedTotal() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let overtime = FocusPreviewActiveTime.placement(activeSeconds: 68 * 60, now: now)
        #expect(overtime.elapsedSeconds(at: now) == 68 * 60)
        #expect(overtime.segmentStartedAt == now)
        let planEnd = FocusPreviewActiveTime.placement(activeSeconds: 46 * 60, now: now)
        #expect(planEnd.elapsedSeconds(at: now) == 46 * 60)
    }

    @Test func stampSoundsAreInTheAppBundle() {
        for name in ["round_stamp", "seal_stamp"] {
            let url = Bundle.main.url(forResource: name, withExtension: "caf")
                ?? Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Sounds")
                ?? Bundle.main.url(
                    forResource: name,
                    withExtension: "caf",
                    subdirectory: "Resources/Sounds"
                )
            #expect(url != nil)
        }
    }
}
