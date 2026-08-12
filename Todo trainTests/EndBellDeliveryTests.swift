//
//  EndBellDeliveryTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct EndBellDeliveryTests {
    @Test func prefersAlarmKitWhenEnabledAndAuthorized() {
        #expect(
            EndBellDelivery.channel(endBellEnabled: true, alarmKitAuthorized: true) == .alarmKit
        )
    }

    @Test func fallsBackToLocalWhenUnauthorized() {
        #expect(
            EndBellDelivery.channel(endBellEnabled: true, alarmKitAuthorized: false)
                == .localNotification
        )
    }

    @Test func usesLocalWhenEndBellDisabled() {
        #expect(
            EndBellDelivery.channel(endBellEnabled: false, alarmKitAuthorized: true)
                == .localNotification
        )
    }

    @Test func inAppSoundOnlyOnLocalChannel() {
        #expect(
            EndBellDelivery.shouldPlayInAppOvertimeSound(
                endBellEnabled: true,
                alarmKitAuthorized: true,
                overtimeSoundEnabled: true
            ) == false
        )
        #expect(
            EndBellDelivery.shouldPlayInAppOvertimeSound(
                endBellEnabled: true,
                alarmKitAuthorized: false,
                overtimeSoundEnabled: true
            ) == true
        )
        #expect(
            EndBellDelivery.shouldPlayInAppOvertimeSound(
                endBellEnabled: false,
                alarmKitAuthorized: false,
                overtimeSoundEnabled: false
            ) == false
        )
    }
}
