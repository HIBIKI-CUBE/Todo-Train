//
//  FocusIdleTimerPolicyTests.swift
//  Todo trainTests
//

import Testing
import UIKit
@testable import Todo_train

struct FocusIdleTimerPolicyTests {
    @Test func chargingOrFull_withSettingOn_disablesIdleTimer() {
        #expect(
            FocusIdleTimerPolicy.shouldDisableIdleTimer(settingEnabled: true, batteryState: .charging)
        )
        #expect(
            FocusIdleTimerPolicy.shouldDisableIdleTimer(settingEnabled: true, batteryState: .full)
        )
    }

    @Test func unplugged_doesNotDisableIdleTimer() {
        #expect(
            !FocusIdleTimerPolicy.shouldDisableIdleTimer(settingEnabled: true, batteryState: .unplugged)
        )
        #expect(
            !FocusIdleTimerPolicy.shouldDisableIdleTimer(settingEnabled: true, batteryState: .unknown)
        )
    }

    @Test func settingOff_doesNotDisableIdleTimerEvenWhenCharging() {
        #expect(
            !FocusIdleTimerPolicy.shouldDisableIdleTimer(settingEnabled: false, batteryState: .charging)
        )
        #expect(
            !FocusIdleTimerPolicy.shouldDisableIdleTimer(settingEnabled: false, batteryState: .full)
        )
    }
}
