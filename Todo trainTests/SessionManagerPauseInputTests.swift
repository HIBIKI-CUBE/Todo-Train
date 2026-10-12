import Foundation
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerPauseInputTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func storedSecondsOnlyRiseAndRideTimeStays() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        clock.advance(by: 40)
        try manager.pause()
        let session = try #require(manager.activeSession)
        let rideAtPause = session.accumulatedActiveSeconds
        let pause = try #require(session.pauses.first { $0.endedAt == nil })
        clock.advance(by: 600)

        let first = command(
            session: session.id,
            pause: pause.id,
            sampled: 300,
            active: 270,
            promptedAt: 1_700_000_200,
            answer: .keepPaused
        )
        #expect(manager.applyPauseInputReport(first).ok)
        let lower = command(
            session: session.id,
            pause: pause.id,
            sampled: 30,
            active: 30,
            promptedAt: 1_700_000_900,
            answer: .resume
        )
        #expect(manager.applyPauseInputReport(lower).ok)
        #expect(pause.macSampledSeconds == 300)
        #expect(pause.macActiveSeconds == 270)
        #expect(pause.promptAnswerRaw == "keepPaused")
        #expect(pause.promptedAt == Date(timeIntervalSince1970: 1_700_000_200))
        #expect(session.accumulatedActiveSeconds == rideAtPause)

        let raised = command(
            session: session.id,
            pause: pause.id,
            sampled: 330,
            active: 300,
            promptedAt: 1_700_000_950,
            answer: PausePromptAnswer.none
        )
        #expect(manager.applyPauseInputReport(raised).ok)
        #expect(pause.macSampledSeconds == 330)
        #expect(pause.macActiveSeconds == 300)
        #expect(pause.promptAnswerRaw == "keepPaused")
        #expect(pause.promptedAt == Date(timeIntervalSince1970: 1_700_000_200))

        try manager.resume()
        #expect(session.accumulatedActiveSeconds == rideAtPause)
        #expect(pause.endedAt != nil)

        let afterEnd = command(
            session: session.id,
            pause: pause.id,
            sampled: 360,
            active: 300,
            promptedAt: 1_700_001_000,
            answer: .resume
        )
        #expect(manager.applyPauseInputReport(afterEnd).ok)
        #expect(pause.macSampledSeconds == 360)
        #expect(pause.macActiveSeconds == 300)
        #expect(pause.promptAnswerRaw == "keepPaused")
        #expect(pause.promptedAt == Date(timeIntervalSince1970: 1_700_000_200))

        let afterEndLower = command(
            session: session.id,
            pause: pause.id,
            sampled: 40,
            active: 10,
            promptedAt: nil,
            answer: nil
        )
        #expect(manager.applyPauseInputReport(afterEndLower).ok)
        #expect(pause.macSampledSeconds == 360)
        #expect(pause.macActiveSeconds == 300)
        #expect(session.accumulatedActiveSeconds == rideAtPause)

        var restarted = PauseInputEngine()
        let anchored = restarted.step(restartObservation(uptime: 1_000, storedSampled: 300, storedActive: 270))
        #expect(anchored.reports.isEmpty)
        #expect(restarted.current?.sampled == 300)
        #expect(restarted.current?.active == 270)
        _ = restarted.step(restartObservation(uptime: 1_030, storedSampled: 300, storedActive: 270))
        #expect(restarted.current?.sampled == 330)
        #expect(restarted.current?.active == 300)
        _ = restarted.step(restartObservation(uptime: 1_031, storedSampled: 30, storedActive: 30))
        #expect(restarted.current?.sampled == 330)
        #expect(restarted.current?.active == 300)
    }

    @Test func impossibleShareAndUnknownPauseAreRefused() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        try manager.board(ticket: ticket)
        try manager.pause()
        let session = try #require(manager.activeSession)
        let pause = try #require(session.pauses.first { $0.endedAt == nil })
        let ride = session.accumulatedActiveSeconds

        let tooActive = command(session: session.id, pause: pause.id, sampled: 10, active: 11, promptedAt: nil, answer: nil)
        #expect(manager.applyPauseInputReport(tooActive).error == .invalidPayload)
        #expect(pause.macSampledSeconds == 0)

        let missing = command(session: session.id, pause: UUID(), sampled: 10, active: 10, promptedAt: nil, answer: nil)
        #expect(manager.applyPauseInputReport(missing).error == .invalidPayload)

        let otherSession = command(session: UUID(), pause: pause.id, sampled: 10, active: 4, promptedAt: nil, answer: nil)
        #expect(manager.applyPauseInputReport(otherSession).error == .sessionMismatch)
        #expect(pause.macSampledSeconds == 0)
        #expect(session.accumulatedActiveSeconds == ride)
    }

    private func command(
        session: UUID,
        pause: UUID,
        sampled: Double,
        active: Double,
        promptedAt: Int?,
        answer: PausePromptAnswer?
    ) -> CommandPlaintext {
        CommandPlaintext(
            id: UUID(),
            op: .pauseInputReport,
            sessionId: session,
            at: 1_700_000_500,
            pauseId: pause,
            macSampledSeconds: sampled,
            macActiveSeconds: active,
            promptedAt: promptedAt,
            promptAnswer: answer
        )
    }

    private func restartObservation(
        uptime: TimeInterval,
        storedSampled: TimeInterval,
        storedActive: TimeInterval
    ) -> PauseInputObservation {
        PauseInputObservation(
            uptime: uptime,
            unixNow: 1_700_000_000 + Int(uptime),
            secondsSinceLastInput: 5,
            counting: true,
            phase: .paused,
            sessionId: UUID(uuidString: "11111111-1111-4111-8111-111111111111"),
            pauseId: UUID(uuidString: "44444444-4444-4444-8444-444444444444"),
            pausedAt: 1_700_000_000,
            heldBy: .user,
            title: "週次",
            storedSampled: storedSampled,
            storedActive: storedActive
        )
    }
}
