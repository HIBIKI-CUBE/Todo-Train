import Foundation
import Testing
@testable import TodoTrainCompanion

struct TimetablePauseDispatchingTests {
    @Test func sendsOncePerBoundary() {
        #expect(
            TimetablePauseDispatching.shouldSend(
                now: 200,
                pauseAt: 180,
                alreadySent: nil,
                canPause: true,
                isSending: false
            )
        )
        #expect(
            !TimetablePauseDispatching.shouldSend(
                now: 200,
                pauseAt: 180,
                alreadySent: 180,
                canPause: true,
                isSending: false
            )
        )
        #expect(
            !TimetablePauseDispatching.shouldSend(
                now: 100,
                pauseAt: 180,
                alreadySent: nil,
                canPause: true,
                isSending: false
            )
        )
        #expect(
            !TimetablePauseDispatching.shouldSend(
                now: 200,
                pauseAt: 180,
                alreadySent: nil,
                canPause: true,
                isSending: true
            )
        )
    }
}
