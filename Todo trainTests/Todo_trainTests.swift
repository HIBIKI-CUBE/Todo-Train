//
//  Todo_trainTests.swift
//  Todo trainTests
//
//  Created by HIBIKI CUBE on 2026/08/11.
//

import Testing
@testable import Todo_train

struct Todo_trainTests {
    @Test func moduleLoads() {
        #expect(PauseLimitGuard.defaultLimit == 2)
    }

    @Test func canBoardNewRide_blocksAtLimit() {
        #expect(PauseLimitGuard.canBoardNewRide(pausedCount: 0, limit: 2))
        #expect(PauseLimitGuard.canBoardNewRide(pausedCount: 1, limit: 2))
        #expect(!PauseLimitGuard.canBoardNewRide(pausedCount: 2, limit: 2))
        #expect(PauseLimitGuard.canBoardNewRide(pausedCount: 2, limit: 3))
    }

    @Test func pauseLiveActivityRetention_expiresAfterTwoHours() {
        let pausedAt = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(!PauseLiveActivityRetention.isExpired(pausedAt: pausedAt, now: pausedAt.addingTimeInterval(2 * 60 * 60 - 1)))
        #expect(PauseLiveActivityRetention.isExpired(pausedAt: pausedAt, now: pausedAt.addingTimeInterval(2 * 60 * 60)))
        #expect(!PauseLiveActivityRetention.isExpired(pausedAt: nil, now: pausedAt))
    }
}
