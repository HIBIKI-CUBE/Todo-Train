//
//  ForegroundReconcileScheduling.swift
//  Todo train
//
//  When the app is foregrounded and a ride (or passenger lane) needs wall-clock
//  progress, SessionManager owns a 1 Hz reconcile loop. Focus / Passenger views
//  may still use TimelineView for display, but they must not own the tick.
//

import Foundation

enum ForegroundReconcileScheduling: Sendable {
    /// Scene phases that matter to the reconcile loop.
    /// `.inactive` is still on screen (Control Center, notification shade).
    enum Scene: Sendable {
        case active
        case inactive
        case background
    }

    /// Open ride or any passenger chrome that advances with time.
    static func needsTick(hasOpenRide: Bool, passengerChrome: PassengerChrome) -> Bool {
        if hasOpenRide { return true }
        if case .none = passengerChrome { return false }
        return true
    }

    /// Wall-clock loop. `allowsWallClock` is false for `FixedSessionClock` so tests do not sleep.
    static func shouldRunLoop(
        isForeground: Bool,
        hasOpenRide: Bool,
        passengerChrome: PassengerChrome,
        allowsWallClock: Bool
    ) -> Bool {
        isForeground
            && allowsWallClock
            && needsTick(hasOpenRide: hasOpenRide, passengerChrome: passengerChrome)
    }

    /// Active starts the loop. Inactive keeps whatever is already running.
    /// Background stops it. Returning from background does not start during inactive;
    /// the active transition clears away before the loop may reconcile.
    static func isForeground(wasForeground: Bool, scene: Scene) -> Bool {
        switch scene {
        case .active: true
        case .inactive: wasForeground
        case .background: false
        }
    }
}
