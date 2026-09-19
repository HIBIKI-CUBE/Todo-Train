//
//  ServicePortalSequenceTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct ServicePortalSequenceTests {
    @Test func advance_followsGateOrder() {
        var phase = ServicePortalPhase.entering
        phase = ServicePortalSequence.advance(phase, .enterElapsed)
        #expect(phase == .awaitingIgnition)
        phase = ServicePortalSequence.advance(phase, .ignited(skipIlluminate: false))
        #expect(phase == .illuminating)
        phase = ServicePortalSequence.advance(phase, .illuminateElapsed)
        #expect(phase == .readyToPrime)
        phase = ServicePortalSequence.advance(phase, .primeBegan)
        #expect(phase == .priming)
        phase = ServicePortalSequence.advance(phase, .primeCancelled)
        #expect(phase == .readyToPrime)
        phase = ServicePortalSequence.advance(phase, .primeBegan)
        phase = ServicePortalSequence.advance(phase, .primeCompleted)
        #expect(phase == .departing)
        phase = ServicePortalSequence.advance(phase, .departElapsed)
        #expect(phase == .done)
    }

    @Test func advance_skipIlluminateJumpsToReadyToPrime() {
        let phase = ServicePortalSequence.advance(
            .awaitingIgnition,
            .ignited(skipIlluminate: true)
        )
        #expect(phase == .readyToPrime)
    }

    @Test func advance_ignoresOutOfOrderEvents() {
        #expect(ServicePortalSequence.advance(.entering, .primeCompleted) == .entering)
        #expect(ServicePortalSequence.advance(.awaitingIgnition, .illuminateElapsed) == .awaitingIgnition)
        #expect(ServicePortalSequence.advance(.illuminating, .primeBegan) == .illuminating)
    }

    @Test func ignition_keepsThePlaceAliveInsteadOfDeadDark() {
        let pre = ServicePortalSequence.premonition(breath: 1)
        let just = ServicePortalSequence.reveal(elapsed: 0, context: richContext)
        #expect(pre.horizon > 0.5)
        #expect(pre.wake > 0.1)
        #expect(just.wake > pre.wake)
        #expect(just.wake >= 0.35)
        #expect(just.horizon == 1)
        #expect(just.shelfRise > 0.15)
        #expect(just.volumeGlow > 0.2)
        #expect(just.beadCount >= 1)
        #expect(!just.serviceLit)
        #expect(!just.canPrime)
        #expect(!just.fullLit)
    }

    @Test func reveal_hasPaceNotASingleFade() {
        let quiet = ServicePortalSequence.reveal(elapsed: 0.12, context: richContext)
        let surged = ServicePortalSequence.reveal(elapsed: 0.48, context: richContext)
        #expect(ServicePortalSequence.pace(elapsed: 0.12, context: richContext) == .quiet)
        #expect(ServicePortalSequence.pace(elapsed: 0.48, context: richContext) == .surge)
        #expect(surged.shelfRise > quiet.shelfRise + 0.12)
        #expect(surged.shelfPitch > quiet.shelfPitch)
        #expect(surged.washTravel > quiet.washTravel + 0.12)
        #expect(surged.volumeGlow > quiet.volumeGlow)
        #expect(surged.wake > quiet.wake)
        #expect(surged.beadCount > quiet.beadCount)

        let beforePeak = ServicePortalSequence.reveal(elapsed: 0.70, context: richContext)
        #expect(ServicePortalSequence.pace(elapsed: 0.70, context: richContext) == .surge)
        #expect(beforePeak.clockProgress < 1)
        #expect(!beforePeak.isPeak)
        #expect(!beforePeak.canPrime)
        #expect(!beforePeak.fullLit)

        let peak = ServicePortalSequence.reveal(elapsed: 0.98, context: richContext)
        #expect(peak.serviceLit)
        #expect(peak.dateLit)
        #expect(peak.clockProgress >= 1)
        #expect(peak.occupancyLive >= 1)
        #expect(peak.isPeak)
        #expect(!peak.fullLit)
        #expect(!peak.canPrime)

        let still = ServicePortalSequence.reveal(elapsed: 1.22, context: richContext)
        #expect(ServicePortalSequence.pace(elapsed: 1.22, context: richContext) == .still)
        #expect(still.fullLit)
        #expect(still.volumeGlow > peak.volumeGlow)
        #expect(!still.canPrime)

        let primed = ServicePortalSequence.reveal(elapsed: 1.80, context: richContext)
        #expect(ServicePortalSequence.pace(elapsed: 1.80, context: richContext) == .primed)
        #expect(primed.canPrime)
        #expect(primed.fullLit)
        #expect(primed.consistLive == 3)
        #expect(primed.wake > still.wake - 0.01)
    }

    @Test func reveal_emptyMorningFillsWithLightAndStaysShort() {
        let empty = emptyContext
        let rich = richContext
        #expect(
            ServicePortalSequence.illuminateDuration(context: empty)
                < ServicePortalSequence.illuminateDuration(context: rich)
        )
        let mid = ServicePortalSequence.reveal(elapsed: 0.40, context: empty)
        #expect(mid.serviceLit)
        #expect(mid.dateLit)
        #expect(mid.beadCount == ServicePortalSequence.beadLimit)
        #expect(mid.wake > 0.55)
        #expect(mid.volumeGlow > 0.45)
        #expect(mid.occupancyLive == 0)
        #expect(mid.consistLive == 0)
        #expect(!mid.canPrime)

        let ready = ServicePortalSequence.reveal(elapsed: 0.96, context: empty)
        #expect(ready.canPrime)
        #expect(ready.isPeak)
        #expect(ready.fullLit)
    }

    @Test func reveal_reduceMotionFillsAndPrimesImmediately() {
        let context = ServicePortalSequence.Context(
            occupancyCount: 2,
            consistCount: 1,
            reduceMotion: true,
            skipIlluminate: false
        )
        let reveal = ServicePortalSequence.reveal(elapsed: 0, context: context)
        #expect(reveal.serviceLit)
        #expect(reveal.dateLit)
        #expect(reveal.occupancyLive == 2)
        #expect(reveal.consistLive == 1)
        #expect(reveal.canPrime)
        #expect(reveal.fullLit)
        #expect(reveal.wake == 1)
        #expect(reveal.shelfPitch == 1)
        #expect(ServicePortalSequence.pace(elapsed: 0, context: context) == .primed)
    }

    @Test func reveal_capsOccupancyHands() {
        let context = ServicePortalSequence.Context(
            occupancyCount: 9,
            consistCount: 9,
            reduceMotion: true,
            skipIlluminate: false
        )
        let reveal = ServicePortalSequence.reveal(elapsed: 0, context: context)
        #expect(reveal.occupancyLive == ServicePortalSequence.occupancyHandLimit)
        #expect(reveal.consistLive == ServicePortalSequence.consistLeadLimit)
        #expect(ServicePortalSequence.occupancyHands(Array(0..<9)) == [0, 1, 2, 3])
    }

    @Test func primeHold_isAShortPressNotATap() {
        #expect(ServicePortalSequence.primeHoldSeconds >= 0.4)
        #expect(ServicePortalSequence.primeHoldSeconds <= 0.7)
    }

    @Test func depart_hasTwoBeatsAndMinimumDuration() {
        #expect(ServicePortalSequence.departHoldSeconds >= 0.45)
        #expect(ServicePortalSequence.reduceMotionDepartHoldSeconds >= 0.20)
        #expect(ServicePortalSequence.departBeat(elapsed: 0.05, reduceMotion: false) == .slit)
        #expect(
            ServicePortalSequence.departBeat(
                elapsed: ServicePortalSequence.departSlitSeconds,
                reduceMotion: false
            ) == .flood
        )
        #expect(ServicePortalSequence.departBeat(elapsed: 0.05, reduceMotion: true) == .slit)
        #expect(
            ServicePortalSequence.departBeat(
                elapsed: ServicePortalSequence.reduceMotionDepartSlitSeconds,
                reduceMotion: true
            ) == .flood
        )
    }

    @Test func sealedPlace_isClosedNotABlankSheet() {
        let sealed = ServicePortalSequence.sealedPlace()
        #expect(sealed.horizon > 0)
        #expect(sealed.wake > 0)
        #expect(!sealed.serviceLit)
        #expect(sealed.beadCount == 0)
    }

    @Test func rollingClock_settlesToLiveTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 20, hour: 8, minute: 7, second: 6)
        )!
        let live = ServicePortalSequence.rollingClockDigits(
            at: date,
            progress: 1,
            salt: 3,
            calendar: calendar
        )
        #expect(live.hourMinute == "08:07")
        #expect(live.second == "06")

        let rolling = ServicePortalSequence.rollingClockDigits(
            at: date,
            progress: 0.2,
            salt: 3,
            calendar: calendar
        )
        #expect(rolling.hourMinute != "08:07")
    }

    private var richContext: ServicePortalSequence.Context {
        ServicePortalSequence.Context(
            occupancyCount: 2,
            consistCount: 3,
            reduceMotion: false,
            skipIlluminate: false
        )
    }

    private var emptyContext: ServicePortalSequence.Context {
        ServicePortalSequence.Context(
            occupancyCount: 0,
            consistCount: 0,
            reduceMotion: false,
            skipIlluminate: false
        )
    }
}
