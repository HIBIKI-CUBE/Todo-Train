//
//  ArrivalStampFeedbackTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

@Suite("Arrival stamp feedback")
struct ArrivalStampFeedbackTests {
    @Test func cornerSealPlaysSealSoundThenTwoHaptics() {
        let events = ArrivalStampFeedback.sequence(hasCornerSeal: true, praiseCount: 0)
        #expect(events == [
            ArrivalStampFeedback.Event(delayMilliseconds: 0, sound: .seal, haptic: .sealHeavy),
            ArrivalStampFeedback.Event(
                delayMilliseconds: ArrivalStampFeedback.sealFollowUpMilliseconds,
                sound: nil,
                haptic: .sealRigid
            ),
        ])
        #expect(events[1].delayMilliseconds - events[0].delayMilliseconds == 70)
    }

    @Test func cornerSealIgnoresPraiseAndDoesNotStackRoundCues() {
        let quiet = ArrivalStampFeedback.sequence(hasCornerSeal: true, praiseCount: 0)
        let praised = ArrivalStampFeedback.sequence(hasCornerSeal: true, praiseCount: 3)
        #expect(quiet == praised)
        let cues = praised
        #expect(cues.allSatisfy { $0.sound != .roundStamp })
        #expect(cues.allSatisfy { $0.haptic != .roundBase && $0.haptic != .roundPraise })
        #expect(cues.filter { $0.sound == .seal }.count == 1)
    }

    @Test func sealIntensitiesStayFixed() {
        #expect(ArrivalStampFeedback.sealHeavyIntensity == 1.0)
        #expect(ArrivalStampFeedback.sealRigidIntensity == 0.75)
        #expect(ArrivalStampFeedback.sealFollowUpMilliseconds == 70)
    }

    @Test func withoutCornerSealKeepsRoundSoundAndExistingHaptics() {
        let plain = ArrivalStampFeedback.sequence(hasCornerSeal: false, praiseCount: 0)
        #expect(plain == [
            ArrivalStampFeedback.Event(delayMilliseconds: 0, sound: .roundStamp, haptic: .roundBase),
        ])
        let praised = ArrivalStampFeedback.sequence(hasCornerSeal: false, praiseCount: 1)
        #expect(praised == [
            ArrivalStampFeedback.Event(delayMilliseconds: 0, sound: .roundStamp, haptic: .roundPraise),
        ])
        #expect(ArrivalStampFeedback.roundBaseIntensity == 1.0)
        #expect(ArrivalStampFeedback.roundPraiseIntensity == 1.0)
    }

    @Test func previewActiveTimeMatchesTheRequestedTotal() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let overtime = FocusPreviewActiveTime.placement(activeSeconds: 68 * 60, now: now)
        #expect(overtime.elapsedSeconds(at: now) == 68 * 60)
        #expect(overtime.segmentStartedAt == now)
        let planEnd = FocusPreviewActiveTime.placement(activeSeconds: 46 * 60, now: now)
        #expect(planEnd.elapsedSeconds(at: now) == 46 * 60)
    }

    @Test func sealStampSoundIsInTheAppBundle() {
        let url = Bundle.main.url(forResource: "seal_stamp", withExtension: "caf")
            ?? Bundle.main.url(forResource: "seal_stamp", withExtension: "caf", subdirectory: "Sounds")
            ?? Bundle.main.url(
                forResource: "seal_stamp",
                withExtension: "caf",
                subdirectory: "Resources/Sounds"
            )
        #expect(url != nil)
    }
}
