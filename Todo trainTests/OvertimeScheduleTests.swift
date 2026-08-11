//
//  OvertimeScheduleTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct OvertimeScheduleTests {
    @Test func fireAt_isNowPlusRemainingBudget() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fire = OvertimeSchedule.fireAt(
            budgetSeconds: 1800,
            elapsedSeconds: 600,
            now: now
        )
        #expect(fire == now.addingTimeInterval(1200))
    }

    @Test func fireAt_nilWhenAlreadyOverBudget() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fire = OvertimeSchedule.fireAt(
            budgetSeconds: 600,
            elapsedSeconds: 600,
            now: now
        )
        #expect(fire == nil)
    }

    @Test func fireAt_nilWhenPastBudget() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fire = OvertimeSchedule.fireAt(
            budgetSeconds: 300,
            elapsedSeconds: 400,
            now: now
        )
        #expect(fire == nil)
    }

    @Test func notificationIdentifier_includesSessionID() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        #expect(OvertimeSchedule.notificationIdentifier(sessionID: id) == "overtime.\(id.uuidString)")
    }
}
