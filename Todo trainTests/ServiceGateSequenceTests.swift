//
//  ServiceGateSequenceTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct ServiceGateSequenceTests {
    @Test func advance_followsGateOrder() {
        var phase = ServiceGatePhase.entering
        phase = ServiceGateSequence.advance(phase, .enterElapsed)
        #expect(phase == .awaitingIgnition)
        phase = ServiceGateSequence.advance(phase, .ignited(skipIlluminate: false))
        #expect(phase == .illuminating)
        phase = ServiceGateSequence.advance(phase, .illuminateElapsed)
        #expect(phase == .readyToPrime)
        phase = ServiceGateSequence.advance(phase, .primeBegan)
        #expect(phase == .priming)
        phase = ServiceGateSequence.advance(phase, .primeCancelled)
        #expect(phase == .readyToPrime)
        phase = ServiceGateSequence.advance(phase, .primeBegan)
        phase = ServiceGateSequence.advance(phase, .primeCompleted)
        #expect(phase == .departing)
        phase = ServiceGateSequence.advance(phase, .departElapsed)
        #expect(phase == .done)
    }

    @Test func advance_skipIlluminateJumpsToReadyToPrime() {
        let phase = ServiceGateSequence.advance(
            .awaitingIgnition,
            .ignited(skipIlluminate: true)
        )
        #expect(phase == .readyToPrime)
    }

    @Test func advance_ignoresOutOfOrderEvents() {
        #expect(ServiceGateSequence.advance(.entering, .primeCompleted) == .entering)
        #expect(ServiceGateSequence.advance(.awaitingIgnition, .illuminateElapsed) == .awaitingIgnition)
        #expect(ServiceGateSequence.advance(.illuminating, .primeBegan) == .illuminating)
    }

    @Test func reveal_staysDarkAtIgnitionStart() {
        let context = ServiceGateSequence.Context(
            occupancyCount: 2,
            consistCount: 2,
            reduceMotion: false,
            skipIlluminate: false
        )
        let reveal = ServiceGateSequence.reveal(elapsed: 0, context: context)
        #expect(!reveal.serviceLit)
        #expect(!reveal.dateLit)
        #expect(reveal.clockProgress == 0)
        #expect(reveal.occupancyLive == 0)
        #expect(reveal.consistLive == 0)
        #expect(!reveal.canPrime)
        #expect(!reveal.isPeak)
        #expect(!reveal.fullLit)
        #expect(reveal.bloom < 0.2)
        #expect(reveal.rise < 0.2)
    }

    @Test func reveal_cabinSurgesThenReadableThenFullLit() {
        let context = ServiceGateSequence.Context(
            occupancyCount: 2,
            consistCount: 3,
            reduceMotion: false,
            skipIlluminate: false
        )
        let quiet = ServiceGateSequence.reveal(elapsed: 0.18, context: context)
        let surged = ServiceGateSequence.reveal(elapsed: 0.48, context: context)
        #expect(surged.rise > quiet.rise + 0.2)
        #expect(surged.bloom > quiet.bloom)
        #expect(surged.wash > quiet.wash)

        let beforePeak = ServiceGateSequence.reveal(elapsed: 0.80, context: context)
        #expect(!beforePeak.isPeak)
        #expect(!beforePeak.canPrime)
        #expect(!beforePeak.fullLit)

        let peak = ServiceGateSequence.reveal(elapsed: 1.05, context: context)
        #expect(peak.serviceLit)
        #expect(peak.dateLit)
        #expect(peak.clockProgress >= 1)
        #expect(peak.occupancyLive >= 1)
        #expect(peak.isPeak)
        #expect(!peak.fullLit)
        #expect(!peak.canPrime)

        let lit = ServiceGateSequence.reveal(elapsed: 1.70, context: context)
        #expect(lit.fullLit)
        #expect(lit.bloom > peak.bloom)
        #expect(lit.wash > peak.wash)
        #expect(!lit.canPrime)

        let primed = ServiceGateSequence.reveal(elapsed: 2.12, context: context)
        #expect(primed.canPrime)
        #expect(primed.fullLit)
        #expect(primed.consistLive == 3)
    }

    @Test func reveal_emptyMorningFillsWithLightNotEmptyBays() {
        let empty = ServiceGateSequence.Context(
            occupancyCount: 0,
            consistCount: 0,
            reduceMotion: false,
            skipIlluminate: false
        )
        let rich = ServiceGateSequence.Context(
            occupancyCount: 2,
            consistCount: 2,
            reduceMotion: false,
            skipIlluminate: false
        )
        #expect(
            ServiceGateSequence.illuminateDuration(context: empty)
                < ServiceGateSequence.illuminateDuration(context: rich)
        )
        let mid = ServiceGateSequence.reveal(elapsed: 0.70, context: empty)
        #expect(mid.serviceLit)
        #expect(mid.dateLit)
        #expect(mid.theatricalLampCount == ServiceGateSequence.theatricalLampLimit)
        #expect(mid.bloom > 0.5)
        #expect(mid.occupancyLive == 0)
        #expect(mid.consistLive == 0)
        #expect(!mid.canPrime)

        let ready = ServiceGateSequence.reveal(elapsed: 1.12, context: empty)
        #expect(ready.canPrime)
        #expect(ready.isPeak)
        #expect(ready.fullLit)
    }

    @Test func reveal_reduceMotionFillsAndPrimesImmediately() {
        let context = ServiceGateSequence.Context(
            occupancyCount: 2,
            consistCount: 1,
            reduceMotion: true,
            skipIlluminate: false
        )
        let reveal = ServiceGateSequence.reveal(elapsed: 0, context: context)
        #expect(reveal.serviceLit)
        #expect(reveal.dateLit)
        #expect(reveal.occupancyLive == 2)
        #expect(reveal.consistLive == 1)
        #expect(reveal.canPrime)
        #expect(reveal.fullLit)
        #expect(reveal.bloom == 1)
    }

    @Test func reveal_capsOccupancyHands() {
        let context = ServiceGateSequence.Context(
            occupancyCount: 9,
            consistCount: 9,
            reduceMotion: true,
            skipIlluminate: false
        )
        let reveal = ServiceGateSequence.reveal(elapsed: 0, context: context)
        #expect(reveal.occupancyLive == ServiceGateSequence.occupancyHandLimit)
        #expect(reveal.consistLive == ServiceGateSequence.consistLeadLimit)
        #expect(ServiceGateSequence.occupancyHands(Array(0..<9)) == [0, 1, 2, 3])
    }

    @Test func depart_hasTwoBeatsAndMinimumDuration() {
        #expect(ServiceGateSequence.departHoldSeconds >= 0.45)
        #expect(ServiceGateSequence.reduceMotionDepartHoldSeconds >= 0.20)
        #expect(ServiceGateSequence.departBeat(elapsed: 0.05, reduceMotion: false) == .unlocking)
        #expect(
            ServiceGateSequence.departBeat(
                elapsed: ServiceGateSequence.departUnlockSeconds,
                reduceMotion: false
            ) == .opening
        )
        #expect(ServiceGateSequence.departBeat(elapsed: 0.05, reduceMotion: true) == .unlocking)
        #expect(
            ServiceGateSequence.departBeat(
                elapsed: ServiceGateSequence.reduceMotionDepartUnlockSeconds,
                reduceMotion: true
            ) == .opening
        )
    }

    @Test func rollingClock_settlesToLiveTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 19, hour: 8, minute: 7, second: 6)
        )!
        let live = ServiceGateSequence.rollingClockDigits(
            at: date,
            progress: 1,
            salt: 3,
            calendar: calendar
        )
        #expect(live.hourMinute == "08:07")
        #expect(live.second == "06")

        let rolling = ServiceGateSequence.rollingClockDigits(
            at: date,
            progress: 0.2,
            salt: 3,
            calendar: calendar
        )
        #expect(rolling.hourMinute != "08:07")
    }
}
