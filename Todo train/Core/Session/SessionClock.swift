//
//  SessionClock.swift
//  Todo train
//

import Foundation

protocol SessionClock: Sendable {
    var now: Date { get }
}

struct SystemSessionClock: SessionClock {
    var now: Date { .now }
}

final class FixedSessionClock: SessionClock, @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
