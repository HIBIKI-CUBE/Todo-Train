//
//  AppSettingsTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

struct AppSettingsTests {
    @Test func clampPauseLimit_onlyTwoOrThree() {
        #expect(AppSettings.clampPauseLimit(2) == 2)
        #expect(AppSettings.clampPauseLimit(3) == 3)
        #expect(AppSettings.clampPauseLimit(4) == 2)
        #expect(AppSettings.clampPauseLimit(1) == 2)
    }

    @Test func makeForTesting_setsValues() {
        let settings = AppSettings.makeForTesting(pauseLimit: 3, overtimeSoundEnabled: false, endBellEnabled: true)
        #expect(settings.pauseLimit == 3)
        #expect(settings.overtimeSoundEnabled == false)
        #expect(settings.endBellEnabled == true)
    }
}
