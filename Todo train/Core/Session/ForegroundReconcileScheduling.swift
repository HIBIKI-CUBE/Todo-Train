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
    /// Open ride or any passenger chrome that advances with time.
    static func needsTick(hasOpenRide: Bool, passengerChrome: PassengerChrome) -> Bool {
        if hasOpenRide { return true }
        if case .none = passengerChrome { return false }
        return true
    }
}
