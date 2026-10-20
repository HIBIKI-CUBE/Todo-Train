import CoreGraphics
import Foundation
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

struct MacPresenceTests {
    @Test func idleSecondsUseTheMostRecentEvent() {
        let idle = MacInputIdle.secondsSinceLastInput { _, type in
            type == .keyDown ? 12 : 90
        }
        #expect(idle == 12)
    }

    @Test func unlockNotificationIsNotTreatedAsLock() {
        #expect(MacScreenLock.isLocked(notificationName: "com.apple.screenIsLocked") == true)
        #expect(MacScreenLock.isLocked(notificationName: "com.apple.screenIsUnlocked") == false)
    }

    @Test func attendingUsesTheSharedWindow() {
        #expect(NudgePlanner.macIsAttending(screenLocked: false, secondsSinceLastInput: 12))
        #expect(!NudgePlanner.macIsAttending(screenLocked: true, secondsSinceLastInput: 12))
    }
}
