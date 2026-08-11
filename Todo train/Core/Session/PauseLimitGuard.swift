//
//  PauseLimitGuard.swift
//  Todo train
//

import Foundation

enum PauseLimitGuard {
    static let defaultLimit = 2

    static func canPause(currentPausedCount: Int, limit: Int = defaultLimit) -> Bool {
        currentPausedCount < limit
    }
}
