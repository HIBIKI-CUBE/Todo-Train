import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Remote pause evaluation")
struct RemotePauseEvaluatingTests {
    let session = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let other = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    var command: CommandPlaintext {
        CommandPlaintext(id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!, sessionId: session, at: 1_768_000_120)
    }

    @Test func applyWhenUnderCap() {
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: session,
            pausedCount: 1,
            pauseLimit: 2,
            command: command
        )
        #expect(decision == .apply)
        let ack = RemotePauseEvaluating.ack(decision: decision, commandId: command.id)
        #expect(ack.ok)
        #expect(ack.error == nil)
        #expect(ack.cmdId == command.id)
    }

    @Test func mismatchWhenSessionDiffers() {
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: other,
            pausedCount: 0,
            pauseLimit: 2,
            command: command
        )
        #expect(decision == .sessionMismatch)
        #expect(RemotePauseEvaluating.ack(decision: decision, commandId: command.id).error == .sessionMismatch)
    }

    @Test func pauseLimitReachedAtCap() {
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: session,
            pausedCount: 2,
            pauseLimit: 2,
            command: command
        )
        #expect(decision == .pauseLimitReached)
        let ack = RemotePauseEvaluating.ack(decision: decision, commandId: command.id)
        #expect(!ack.ok)
        #expect(ack.error == .pauseLimitReached)
    }

    @Test func noActiveServiceWhenNoOpenSession() {
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: nil,
            pausedCount: 0,
            pauseLimit: 2,
            command: command
        )
        #expect(decision == .noActiveService)
        #expect(RemotePauseEvaluating.ack(decision: decision, commandId: command.id).error == .noActiveService)
    }
}
