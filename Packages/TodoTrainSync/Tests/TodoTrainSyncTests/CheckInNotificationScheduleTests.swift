import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Check-in notification schedule")
struct CheckInNotificationScheduleTests {
    private let seed = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func awayFireAtUsesAwayDelay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fireAt = CheckInNotificationSchedule.awayFireAt(now: now, seed: seed)
        let delay = CheckInNotificationSchedule.awayDelay(seed: seed)
        #expect(fireAt == now.addingTimeInterval(delay))
    }

    @Test func progressFireAtMatchesWallClock() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            CheckInNotificationSchedule.progressFireAt(offset: 400, elapsedSeconds: 400, now: now) == nil
        )
        #expect(
            CheckInNotificationSchedule.progressFireAt(offset: 400, elapsedSeconds: 100, now: now)
                == now.addingTimeInterval(300)
        )
    }
}
