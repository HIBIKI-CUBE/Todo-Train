//
//  OpeningPanelHubFlowTests.swift
//  Todo train
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct OpeningPanelHubFlowTests {
    @Test func requestStartIntent_promptsEndWhenPreviousDayOpen() throws {
        #expect(OpeningPanelHubFlow.startIntent(needsServiceDayEndPrompt: true) == .promptEndPreviousDay)
        #expect(OpeningPanelHubFlow.startIntent(needsServiceDayEndPrompt: false) == .showPanel)
    }

    @Test func serviceStartFromMaster_needsEndPreviousDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(day1)
        let manager = SessionManager(
            modelContext: context,
            clock: clock,
            calendar: calendar,
            settings: AppSettings.makeForTesting()
        )
        try manager.startService()
        clock.advance(by: day2.timeIntervalSince(day1))
        manager.reconcile()

        let result = OpeningPanelServiceStart.begin(sessionManager: manager)
        #expect(result == .needsEndPreviousDay)
        #expect(manager.needsServiceDayEndPrompt)
    }
}