import Foundation
import Testing
@testable import TodoTrainSync

@Suite("issueAndBoard gate")
struct IssueAndBoardEvaluatingTests {
    private let cmdID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    private let session = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    private func command(
        sessionId: UUID?,
        title: String? = "週次レビューの下書き",
        estimatedSeconds: Int? = 1500
    ) -> CommandPlaintext {
        CommandPlaintext(
            id: cmdID,
            op: .issueAndBoard,
            sessionId: sessionId,
            at: 1_768_000_120,
            title: title,
            estimatedSeconds: estimatedSeconds
        )
    }

    @Test func boardsWhenServiceIsOpenAndIdle() {
        let decision = IssueAndBoardEvaluating.evaluate(
            serviceActive: true,
            openSessionId: nil,
            command: command(sessionId: nil)
        )
        #expect(decision == .board)
        let ack = IssueAndBoardEvaluating.ack(decision: decision, commandId: cmdID)
        #expect(ack.ok)
        #expect(ack.error == nil)
    }

    @Test func refusesWhenServiceIsClosed() {
        let decision = IssueAndBoardEvaluating.evaluate(
            serviceActive: false,
            openSessionId: nil,
            command: command(sessionId: nil)
        )
        #expect(decision == .noActiveService)
        #expect(IssueAndBoardEvaluating.ack(decision: decision, commandId: cmdID).error == .noActiveService)
    }

    @Test func interruptsWhenSessionMatches() {
        let decision = IssueAndBoardEvaluating.evaluate(
            serviceActive: true,
            openSessionId: session,
            command: command(sessionId: session, title: "割り込みの下書き", estimatedSeconds: 600)
        )
        #expect(decision == .board)
    }

    @Test func sessionMismatchWhenRidingAndIdDiffers() {
        let decision = IssueAndBoardEvaluating.evaluate(
            serviceActive: true,
            openSessionId: session,
            command: command(sessionId: nil)
        )
        #expect(decision == .sessionMismatch)
    }

    @Test func sessionMismatchWhenIdleButIdPresent() {
        let other = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let decision = IssueAndBoardEvaluating.evaluate(
            serviceActive: true,
            openSessionId: nil,
            command: command(sessionId: other)
        )
        #expect(decision == .sessionMismatch)
    }

    @Test func invalidWhenTitleBlankOrSecondsOutOfRange() {
        let blank = IssueAndBoardEvaluating.evaluate(
            serviceActive: true,
            openSessionId: nil,
            command: command(sessionId: nil, title: "   ")
        )
        #expect(blank == .invalidPayload)

        let short = IssueAndBoardEvaluating.evaluate(
            serviceActive: true,
            openSessionId: nil,
            command: command(sessionId: nil, estimatedSeconds: 59)
        )
        #expect(short == .invalidPayload)

        let long = IssueAndBoardEvaluating.evaluate(
            serviceActive: true,
            openSessionId: nil,
            command: command(sessionId: nil, estimatedSeconds: 3601)
        )
        #expect(long == .invalidPayload)

        let edge = IssueAndBoardEvaluating.evaluate(
            serviceActive: true,
            openSessionId: nil,
            command: command(sessionId: nil, estimatedSeconds: 90)
        )
        #expect(edge == .board)
    }

    @Test func pauseEvaluatorDoesNotApplyIssueAndBoard() {
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: session,
            pausedCount: 0,
            pauseLimit: 3,
            command: command(sessionId: session)
        )
        #expect(decision == .noActiveService)
        #expect(!decision.shouldApply)
    }
}
