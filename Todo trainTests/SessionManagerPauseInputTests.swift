import Foundation
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerPauseInputTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func lastReportWinsAndRideTimeStays() throws {
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
            sampled: 30,
            active: 30,
            promptedAt: 1_700_000_200,
            answer: .keepPaused
        )
        #expect(manager.applyPauseInputReport(first).ok)
        let second = command(
            session: session.id,
            pause: pause.id,
            sampled: 90,
            active: 60,
            promptedAt: nil,
            answer: nil
        )
        #expect(manager.applyPauseInputReport(second).ok)
        #expect(pause.macSampledSeconds == 90)
        #expect(pause.macActiveSeconds == 60)
        #expect(pause.promptAnswerRaw == "keepPaused")
        #expect(pause.promptedAt == Date(timeIntervalSince1970: 1_700_000_200))
        #expect(session.accumulatedActiveSeconds == rideAtPause)

        try manager.resume()
        #expect(session.accumulatedActiveSeconds == rideAtPause)
        #expect(pause.endedAt != nil)
        #expect(pause.macSampledSeconds == 90)
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
}
