//
//  EndBellDelivery.swift
//  Todo train
//
//  Decides which overtime channel owns the end-of-estimate signal.
//

import Foundation

enum EndBellDeliveryChannel: Equatable, Sendable {
    /// AlarmKit owns countdown LA + end alert. No local overtime notification / app overtime sound.
    case alarmKit
    /// UserNotifications Time Sensitive (and in-app overtime UI/sound when foreground).
    case localNotification
}

enum EndBellDelivery {
    /// - Parameters:
    ///   - endBellEnabled: Settings toggle.
    ///   - alarmKitAuthorized: AlarmKit authorization is `.authorized`.
    static func channel(
        endBellEnabled: Bool,
        alarmKitAuthorized: Bool
    ) -> EndBellDeliveryChannel {
        if endBellEnabled, alarmKitAuthorized {
            return .alarmKit
        }
        return .localNotification
    }

    static func shouldPlayInAppOvertimeSound(
        endBellEnabled: Bool,
        alarmKitAuthorized: Bool,
        overtimeSoundEnabled: Bool
    ) -> Bool {
        guard overtimeSoundEnabled else { return false }
        return channel(endBellEnabled: endBellEnabled, alarmKitAuthorized: alarmKitAuthorized)
            == .localNotification
    }
}
