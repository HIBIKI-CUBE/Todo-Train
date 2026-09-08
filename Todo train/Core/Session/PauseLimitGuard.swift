//
//  PauseLimitGuard.swift
//  Todo train
//

import Foundation

enum PauseLimitGuard {
    static let defaultLimit = 2

    /// New rides are blocked when paused tickets already sit at the WIP cap.
    /// Pause itself is always allowed. Resume of an existing paused ticket is not a new ride.
    static func canBoardNewRide(pausedCount: Int, limit: Int = defaultLimit) -> Bool {
        pausedCount < limit
    }
}

/// Paused Live Activities stay for StandBy resume, but must not ride ActivityKit's 8h cap.
enum PauseLiveActivityRetention {
    static let maxDuration: TimeInterval = 2 * 60 * 60

    static func isExpired(pausedAt: Date?, now: Date) -> Bool {
        guard let pausedAt else { return false }
        return now.timeIntervalSince(pausedAt) >= maxDuration
    }

    static func keepUntil(pausedAt: Date, now: Date = .now) -> Date {
        min(
            pausedAt.addingTimeInterval(maxDuration),
            now.addingTimeInterval(maxDuration)
        )
    }
}
