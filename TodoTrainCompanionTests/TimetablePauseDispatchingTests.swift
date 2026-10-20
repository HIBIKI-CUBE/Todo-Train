import Foundation
import Testing
@testable import TodoTrainCompanion

struct TimetablePauseDispatchingTests {
    @Test func timetableTimeDoesNotSendPause() {
        for sample in [
            (now: 200, pauseAt: Optional(180), alreadySent: Optional<Int>.none, canPause: true, isSending: false),
            (now: 200, pauseAt: Optional(180), alreadySent: Optional(180), canPause: true, isSending: false),
            (now: 100, pauseAt: Optional(180), alreadySent: Optional<Int>.none, canPause: true, isSending: false),
            (now: 200, pauseAt: Optional(180), alreadySent: Optional<Int>.none, canPause: true, isSending: true),
            (now: 180, pauseAt: Optional(180), alreadySent: Optional<Int>.none, canPause: true, isSending: false)
        ] {
            #expect(
                !TimetablePauseDispatching.shouldSend(
                    now: sample.now,
                    pauseAt: sample.pauseAt,
                    alreadySent: sample.alreadySent,
                    canPause: sample.canPause,
                    isSending: sample.isSending
                )
            )
        }
    }
}
