//
//  OvertimeSchedule.swift
//  Todo train
//

import Foundation

enum OvertimeSchedule {
    /// When the session budget will be exhausted, given current elapsed active seconds.
    /// Returns `nil` if already at or past budget (caller should not schedule).
    static func fireAt(
        budgetSeconds: Int,
        elapsedSeconds: TimeInterval,
        now: Date
    ) -> Date? {
        let remaining = TimeInterval(budgetSeconds) - elapsedSeconds
        guard remaining > 0 else { return nil }
        return now.addingTimeInterval(remaining)
    }

    static func notificationIdentifier(sessionID: UUID) -> String {
        "overtime.\(sessionID.uuidString)"
    }
}
