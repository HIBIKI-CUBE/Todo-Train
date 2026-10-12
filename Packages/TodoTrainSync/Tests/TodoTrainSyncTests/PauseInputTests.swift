import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Pause input sampling")
struct PauseInputSamplingTests {
    @Test func thirtySecondsOfRecentInputCountsTheBucket() {
        let bucket = PauseInputSampling.advance(
            sampled: 0,
            active: 0,
            lastUptime: 10,
            uptime: 40,
            secondsSinceLastInput: 12,
            counting: true
        )
        #expect(bucket.sampled == 30)
        #expect(bucket.active == 30)
        #expect(bucket.active <= bucket.sampled)
    }

    @Test func quietBucketAddsSampledTimeOnly() {
        let bucket = PauseInputSampling.advance(
            sampled: 30,
            active: 30,
            lastUptime: 40,
            uptime: 70,
            secondsSinceLastInput: 60,
            counting: true
        )
        #expect(bucket.sampled == 60)
        #expect(bucket.active == 30)
    }

    @Test func lockAndSleepAndDisconnectAreNotAddedLater() {
        let skipped = PauseInputSampling.advance(
            sampled: 30,
            active: 30,
            lastUptime: 40,
            uptime: 100,
            secondsSinceLastInput: 1,
            counting: false
        )
        #expect(skipped.sampled == 30)
        #expect(skipped.active == 30)
        let next = PauseInputSampling.advance(
            sampled: skipped.sampled,
            active: skipped.active,
            lastUptime: skipped.lastUptime,
            uptime: 130,
            secondsSinceLastInput: 1,
            counting: true
        )
        #expect(next.sampled == 60)
        #expect(next.active == 60)
    }

    @Test func aStalledGapIsDropped() {
        let bucket = PauseInputSampling.advance(
            sampled: 30,
            active: 0,
            lastUptime: 0,
            uptime: 90,
            secondsSinceLastInput: 1,
            counting: true
        )
        #expect(bucket.sampled == 30)
        #expect(bucket.lastUptime == 90)
    }

    @Test func activeNeverPassesSampled() {
        let bucket = PauseInputSampling.advance(
            sampled: 30,
            active: 30,
            lastUptime: 0,
            uptime: 30,
            secondsSinceLastInput: 0,
            counting: true
        )
        #expect(bucket.active <= bucket.sampled)
    }
}

@Suite("Pause input question")
struct PauseInputPromptTests {
    private let session = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let pause = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private let otherPause = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!

    @Test func userPauseWithShareAsksOnce() {
        var engine = primed(heldBy: .user, sampled: 300, active: 240)
        let first = engine.step(watching(uptime: 330, unix: 1_000_300, heldBy: .user))
        #expect(first.chime)
        #expect(first.prompt == "『週次』、停車のまま？")
        let second = engine.step(watching(uptime: 331, unix: 1_000_301, heldBy: .user))
        #expect(!second.chime)
        #expect(second.prompt == first.prompt)
        #expect(second.reports.isEmpty)
    }

    @Test func bareTitleAsksWithoutAName() {
        var engine = primed(heldBy: .user, sampled: 300, active: 240, title: "  ")
        let step = engine.step(watching(uptime: 330, unix: 1_000_300, heldBy: .user, title: "  "))
        #expect(step.prompt == "停車のまま？")
    }

    @Test func otherHoldersDoNotAsk() {
        for heldBy in [PauseHeldBy.timetable, .alarm, .rideSwitch, .passenger] {
            var engine = primed(heldBy: heldBy, sampled: 300, active: 300)
            let step = engine.step(watching(uptime: 330, unix: 1_000_300, heldBy: heldBy))
            #expect(step.prompt == nil)
            #expect(!step.chime)
        }
    }

    @Test func shortPauseOrLowShareDoesNotAsk() {
        var young = primed(heldBy: .user, sampled: 300, active: 300, pausedAt: 1_000_200)
        let tooSoon = young.step(watching(uptime: 301, unix: 1_000_300, heldBy: .user, pausedAt: 1_000_200))
        #expect(tooSoon.prompt == nil)

        var thin = primed(heldBy: .user, sampled: 100, active: 79)
        let low = thin.step(watching(uptime: 301, unix: 1_000_300, heldBy: .user))
        #expect(low.prompt == nil)

        var enough = primed(heldBy: .user, sampled: 100, active: 80)
        let line = enough.step(watching(uptime: 301, unix: 1_000_300, heldBy: .user))
        #expect(line.prompt != nil)
    }

    @Test func keepPausedDoesNotAskAgain() {
        var engine = primed(heldBy: .user, sampled: 300, active: 300)
        _ = engine.step(watching(uptime: 330, unix: 1_000_300, heldBy: .user))
        let report = engine.answer(.keepPaused)
        #expect(report?.promptAnswer == .keepPaused)
        #expect(engine.promptLine == nil)
        let again = engine.step(watching(uptime: 360, unix: 1_000_330, heldBy: .user))
        #expect(again.prompt == nil)
        #expect(!again.chime)
    }

    @Test func resumeReportsAndDoesNotAddThePauseToTheLedgerTwiceAsAQuestion() {
        var engine = primed(heldBy: .user, sampled: 300, active: 300)
        _ = engine.step(watching(uptime: 330, unix: 1_000_300, heldBy: .user))
        let answered = engine.answer(.resume)
        #expect(answered?.promptAnswer == .resume)
        #expect(answered?.macActiveSeconds == 330)
        let ended = engine.step(running(unix: 1_000_400))
        #expect(ended.reports.count == 1)
        #expect(ended.reports[0].promptAnswer == .resume)
        #expect(ended.prompt == nil)
    }

    @Test func unansweredEndReportsNone() {
        var engine = primed(heldBy: .user, sampled: 300, active: 300)
        _ = engine.step(watching(uptime: 330, unix: 1_000_300, heldBy: .user))
        let ended = engine.step(idle())
        #expect(ended.reports.count == 1)
        #expect(ended.reports[0].promptAnswer == PausePromptAnswer.none)
        #expect(ended.reports[0].promptedAt != nil)
    }

    @Test func aRunningRideIsNotSampled() {
        var engine = primed(heldBy: .user, sampled: 30, active: 0)
        let step = engine.step(
            PauseInputObservation(
                uptime: 100,
                unixNow: 1_000_100,
                secondsSinceLastInput: 1,
                counting: true,
                phase: .running,
                sessionId: UUID(),
                title: "別"
            )
        )
        #expect(step.reports.isEmpty)
        #expect(engine.current == nil)
        #expect(engine.background.first?.sampled == 30)
    }

    @Test func onlyTheLatestPauseIsSampled() {
        var engine = primed(heldBy: .user, sampled: 30, active: 30)
        let step = engine.step(
            watching(
                uptime: 80,
                unix: 1_000_080,
                heldBy: .user,
                pauseId: otherPause,
                pausedAt: 1_000_000
            )
        )
        #expect(step.reports.isEmpty)
        #expect(engine.current?.pauseId == otherPause)
        #expect(engine.current?.sampled == 0)
        #expect(engine.background.first?.pauseId == pause)
        #expect(engine.background.first?.sampled == 30)
    }

    @Test func gaugeStartsAtFifteenMinutes() {
        #expect(PauseInputCopy.gauge(elapsed: 15 * 60 - 1) == nil)
        #expect(PauseInputCopy.gauge(elapsed: 15 * 60) == "停車 15:00")
    }

    @Test func reportRejectsAnImpossibleShare() {
        #expect(PauseInputReport.make(
            sessionId: session,
            pauseId: pause,
            macSampledSeconds: 10,
            macActiveSeconds: 11,
            promptedAt: nil,
            promptAnswer: nil
        ) == nil)
        #expect(PauseInputReport.make(
            sessionId: session,
            pauseId: pause,
            macSampledSeconds: 10,
            macActiveSeconds: 10,
            promptedAt: nil,
            promptAnswer: .unknown("later")
        ) == nil)
    }

    @Test func fixtureRoundTrip() throws {
        let data = try ContractFixtures.data("fixtures/cmd-pause-input.json")
        let decoded = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
        #expect(decoded.op == .pauseInputReport)
        #expect(decoded.macSampledSeconds == 300)
        #expect(decoded.macActiveSeconds == 270)
        #expect(decoded.promptAnswer == .keepPaused)
        let report = try #require(PauseInputReport.make(
            sessionId: decoded.sessionId,
            pauseId: decoded.pauseId,
            macSampledSeconds: decoded.macSampledSeconds,
            macActiveSeconds: decoded.macActiveSeconds,
            promptedAt: decoded.promptedAt,
            promptAnswer: decoded.promptAnswer
        ))
        #expect(report.macActiveSeconds <= report.macSampledSeconds)
        let encoded = try WireJSON.encoder().encode(decoded)
        let again = try WireJSON.decoder().decode(CommandPlaintext.self, from: encoded)
        #expect(again == decoded)
    }

    @Test func brokenPauseIdDoesNotFailTheSnap() throws {
        let json = Data(#"{"rev":1,"sessionId":"11111111-1111-4111-8111-111111111111","ticketId":null,"title":"a","phase":"paused","startedAt":1,"estimatedSeconds":60,"pausedAccumulated":0,"pausedAt":2,"boardedDeviceID":null,"serviceActive":true,"cabinEnabled":true,"checkInFiredCount":0,"pendingCabin":null,"pauseId":"not-a-uuid"}"#.utf8)
        let snap = try WireJSON.decoder().decode(SnapPlaintext.self, from: json)
        #expect(snap.phase == .paused)
        #expect(snap.pauseId == nil)
    }

    private func primed(
        heldBy: PauseHeldBy,
        sampled: TimeInterval,
        active: TimeInterval,
        pausedAt: Int = 1_000_000,
        title: String = "週次"
    ) -> PauseInputEngine {
        var engine = PauseInputEngine()
        var watch = PauseInputWatch(pauseId: pause, sessionId: session)
        watch.sampled = sampled
        watch.active = active
        watch.lastUptime = 300
        watch.pausedAt = pausedAt
        watch.heldBy = heldBy
        watch.title = title
        engine.current = watch
        return engine
    }

    private func watching(
        uptime: TimeInterval,
        unix: Int,
        heldBy: PauseHeldBy,
        pauseId: UUID? = nil,
        pausedAt: Int = 1_000_000,
        title: String = "週次"
    ) -> PauseInputObservation {
        PauseInputObservation(
            uptime: uptime,
            unixNow: unix,
            secondsSinceLastInput: 5,
            counting: true,
            phase: .paused,
            sessionId: session,
            pauseId: pauseId ?? pause,
            pausedAt: pausedAt,
            heldBy: heldBy,
            title: title
        )
    }

    private func running(unix: Int) -> PauseInputObservation {
        PauseInputObservation(
            uptime: 400,
            unixNow: unix,
            secondsSinceLastInput: 1,
            counting: true,
            phase: .running,
            sessionId: session
        )
    }

    private func idle() -> PauseInputObservation {
        PauseInputObservation(
            uptime: 400,
            unixNow: 1_000_400,
            secondsSinceLastInput: 1,
            counting: false,
            phase: .idle
        )
    }
}
