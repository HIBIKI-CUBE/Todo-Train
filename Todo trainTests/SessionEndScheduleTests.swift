//
//  SessionEndScheduleTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct SessionEndScheduleTests {
    @Test func fireAt_matchesOvertimeSchedule() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fireAt = SessionEndSchedule.fireAt(
            budgetSeconds: 600,
            elapsedSeconds: 120,
            now: now
        )
        #expect(fireAt == now.addingTimeInterval(480))
    }

    @Test func countdownSeconds_returnsRemaining() {
        #expect(SessionEndSchedule.countdownSeconds(budgetSeconds: 600, elapsedSeconds: 100) == 500)
        #expect(SessionEndSchedule.countdownSeconds(budgetSeconds: 600, elapsedSeconds: 700) == nil)
    }

    @Test func alarmID_isStablePerSession() {
        let id = UUID()
        #expect(SessionEndSchedule.alarmID(sessionID: id) == id)
    }
}
