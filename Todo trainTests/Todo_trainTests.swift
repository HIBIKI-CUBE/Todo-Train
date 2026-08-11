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
}
