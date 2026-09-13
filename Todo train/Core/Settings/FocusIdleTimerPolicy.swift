//
//  FocusIdleTimerPolicy.swift
//  Todo train
//

import SwiftUI
import UIKit

enum FocusIdleTimerPolicy {
    /// Idle timer is disabled only while Focus is visible (caller), the setting is on,
    /// and the device is on charger (charging or full).
    static func shouldDisableIdleTimer(
        settingEnabled: Bool,
        batteryState: UIDevice.BatteryState
    ) -> Bool {
        guard settingEnabled else { return false }
        switch batteryState {
        case .charging, .full:
            return true
        default:
            return false
        }
    }
}

struct FocusKeepAwakeModifier: ViewModifier {
    var settingEnabled: Bool

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { startMonitoring() }
            .onDisappear { stopMonitoring() }
            .onChange(of: settingEnabled) { _, _ in apply() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    startMonitoring()
                } else {
                    releaseIdleTimer()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            ) { _ in
                apply()
            }
    }

    private func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        apply()
    }

    private func stopMonitoring() {
        releaseIdleTimer()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func apply() {
        guard scenePhase == .active else {
            releaseIdleTimer()
            return
        }
        UIApplication.shared.isIdleTimerDisabled = FocusIdleTimerPolicy.shouldDisableIdleTimer(
            settingEnabled: settingEnabled,
            batteryState: UIDevice.current.batteryState
        )
    }

    private func releaseIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
