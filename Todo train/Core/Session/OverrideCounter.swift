//
//  OverrideCounter.swift
//  Todo train
//

import Foundation

protocol OverrideCounting: AnyObject {
    func count(forDayKey dayKey: String) -> Int
    func increment(forDayKey dayKey: String) -> Int
    func reset(forDayKey dayKey: String)
}

/// Persists temporary-pause override counts per calendar day key.
final class OverrideCounter: OverrideCounting {
    static let shared = OverrideCounter()

    private let defaults: UserDefaults
    private let keyPrefix = "overrideCount."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func count(forDayKey dayKey: String) -> Int {
        defaults.integer(forKey: storageKey(dayKey))
    }

    @discardableResult
    func increment(forDayKey dayKey: String) -> Int {
        let next = count(forDayKey: dayKey) + 1
        defaults.set(next, forKey: storageKey(dayKey))
        return next
    }

    func reset(forDayKey dayKey: String) {
        defaults.removeObject(forKey: storageKey(dayKey))
    }

    private func storageKey(_ dayKey: String) -> String {
        keyPrefix + dayKey
    }
}

/// In-memory counter for tests.
final class InMemoryOverrideCounter: OverrideCounting {
    private var counts: [String: Int] = [:]

    func count(forDayKey dayKey: String) -> Int {
        counts[dayKey] ?? 0
    }

    @discardableResult
    func increment(forDayKey dayKey: String) -> Int {
        let next = count(forDayKey: dayKey) + 1
        counts[dayKey] = next
        return next
    }

    func reset(forDayKey dayKey: String) {
        counts[dayKey] = nil
    }
}
