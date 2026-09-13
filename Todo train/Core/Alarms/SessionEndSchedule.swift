//
//  SessionEndSchedule.swift
//  Todo train
//

import Foundation

/// When a running session's budget will be reached (end bell / AlarmKit target).
enum SessionEndSchedule {
  static func fireAt(
    budgetSeconds: Int,
    elapsedSeconds: TimeInterval,
    now: Date
  ) -> Date? {
    OvertimeSchedule.fireAt(
      budgetSeconds: budgetSeconds,
      elapsedSeconds: elapsedSeconds,
      now: now
    )
  }

  static func countdownSeconds(
    budgetSeconds: Int,
    elapsedSeconds: TimeInterval
  ) -> TimeInterval? {
    let remaining = TimeInterval(budgetSeconds) - elapsedSeconds
    guard remaining > 0 else { return nil }
    return remaining
  }

  static func alarmID(sessionID: UUID) -> UUID {
    sessionID
  }
}
