import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Ride end notification schedule")
struct RideEndNotificationScheduleTests {
    @Test func fireAt_matchesRemainingBudget() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fireAt = RideEndNotificationSchedule.fireAt(
            budgetSeconds: 600,
            elapsedSeconds: 100,
            now: now
        )
        #expect(fireAt == now.addingTimeInterval(500))
    }

    @Test func fireAt_nilWhenPastBudget() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            RideEndNotificationSchedule.fireAt(
                budgetSeconds: 600,
                elapsedSeconds: 700,
                now: now
            ) == nil
        )
    }

    @Test func countdownSeconds_matchesRemaining() {
        #expect(RideEndNotificationSchedule.countdownSeconds(budgetSeconds: 600, elapsedSeconds: 100) == 500)
        #expect(RideEndNotificationSchedule.countdownSeconds(budgetSeconds: 600, elapsedSeconds: 700) == nil)
    }
}
