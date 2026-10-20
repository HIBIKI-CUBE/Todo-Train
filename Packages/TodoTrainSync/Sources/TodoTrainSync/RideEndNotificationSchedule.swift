import Foundation

/// When a running session budget will be exhausted (overtime notification / end bell).
public enum RideEndNotificationSchedule: Sendable {
    public static func fireAt(
        budgetSeconds: Int,
        elapsedSeconds: TimeInterval,
        now: Date
    ) -> Date? {
        let remaining = TimeInterval(budgetSeconds) - elapsedSeconds
        guard remaining > 0 else { return nil }
        return now.addingTimeInterval(remaining)
    }

    public static func countdownSeconds(
        budgetSeconds: Int,
        elapsedSeconds: TimeInterval
    ) -> TimeInterval? {
        let remaining = TimeInterval(budgetSeconds) - elapsedSeconds
        guard remaining > 0 else { return nil }
        return remaining
    }

    public static func overtimeNotificationIdentifier(sessionID: UUID) -> String {
        "overtime.\(sessionID.uuidString)"
    }

    public static func alarmID(sessionID: UUID) -> UUID {
        sessionID
    }
}
