import Foundation
import Testing
@testable import TodoTrainCompanion

struct CompanionPauseInputTests {
    @Test func countingSkipsSleepLockAndDisconnect() {
        #expect(PauseInputCounting.allows(
            connected: true,
            screenLocked: false,
            systemAsleep: false,
            screensAsleep: false
        ))
        #expect(!PauseInputCounting.allows(
            connected: false,
            screenLocked: false,
            systemAsleep: false,
            screensAsleep: false
        ))
        #expect(!PauseInputCounting.allows(
            connected: true,
            screenLocked: true,
            systemAsleep: false,
            screensAsleep: false
        ))
        #expect(!PauseInputCounting.allows(
            connected: true,
            screenLocked: false,
            systemAsleep: true,
            screensAsleep: false
        ))
        #expect(!PauseInputCounting.allows(
            connected: true,
            screenLocked: false,
            systemAsleep: false,
            screensAsleep: true
        ))
    }
}
