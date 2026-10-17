//
//  OvertimeSchedule.swift
//  Todo train
//

import Foundation
import TodoTrainSync

enum OvertimeSchedule {
    static func fireAt(
        budgetSeconds: Int,
        elapsedSeconds: TimeInterval,
        now: Date
    ) -> Date? {
        RideEndNotificationSchedule.fireAt(
            budgetSeconds: budgetSeconds,
            elapsedSeconds: elapsedSeconds,
            now: now
        )
    }

    static func notificationIdentifier(sessionID: UUID) -> String {
        RideEndNotificationSchedule.overtimeNotificationIdentifier(sessionID: sessionID)
    }
}
