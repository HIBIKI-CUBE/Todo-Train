//
//  SessionEndSchedule.swift
//  Todo train
//

import Foundation
import TodoTrainSync

/// When a running session's budget will be reached (end bell / AlarmKit target).
enum SessionEndSchedule {
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

  static func countdownSeconds(
    budgetSeconds: Int,
    elapsedSeconds: TimeInterval
  ) -> TimeInterval? {
    RideEndNotificationSchedule.countdownSeconds(
      budgetSeconds: budgetSeconds,
      elapsedSeconds: elapsedSeconds
    )
  }

  static func alarmID(sessionID: UUID) -> UUID {
    RideEndNotificationSchedule.alarmID(sessionID: sessionID)
  }
}
