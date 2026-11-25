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

@Suite("issue gate")
struct IssueEvaluatingTests {
    private let cmdID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!

    private func command(
        sessionId: UUID? = nil,
        title: String? = "週次レビューの下書き",
        estimatedSeconds: Int? = 1500,
        op: WireOp = .issue
    ) -> CommandPlaintext {
        CommandPlaintext(
            id: cmdID,
            op: op,
            sessionId: sessionId,
            at: 1_768_000_120,
            title: title,
            estimatedSeconds: estimatedSeconds
        )
    }

    @Test func savesWithoutServiceOrARide() {
        let decision = IssueEvaluating.evaluate(command: command(), receiverContract: 17)
        #expect(decision == .save)
        let ack = IssueEvaluating.ack(decision: decision, commandId: cmdID)
        #expect(ack.ok)
        #expect(ack.error == nil)
    }

    @Test func olderReceiverIsUnsupported() {
        let decision = IssueEvaluating.evaluate(command: command(), receiverContract: 16)
        #expect(decision == .unsupportedOp)
        #expect(IssueEvaluating.ack(decision: decision, commandId: cmdID).error == .unsupportedOp)
    }

    @Test func rejectsASessionIdAndABadPayload() {
        let session = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        #expect(IssueEvaluating.evaluate(command: command(sessionId: session)) == .invalidPayload)
        #expect(IssueEvaluating.evaluate(command: command(title: "  ")) == .invalidPayload)
        #expect(IssueEvaluating.evaluate(command: command(estimatedSeconds: 59)) == .invalidPayload)
        #expect(IssueEvaluating.evaluate(command: command(estimatedSeconds: 3601)) == .invalidPayload)
        #expect(IssueEvaluating.evaluate(command: command(title: nil)) == .invalidPayload)
        #expect(IssueEvaluating.evaluate(command: command(op: .issueAndBoard)) == .invalidPayload)
        #expect(IssueEvaluating.evaluate(command: command(estimatedSeconds: 60)) == .save)
        #expect(IssueEvaluating.evaluate(command: command(estimatedSeconds: 3600)) == .save)
    }
}
