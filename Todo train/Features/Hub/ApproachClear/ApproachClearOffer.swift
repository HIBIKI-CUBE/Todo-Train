//
//  ApproachClearOffer.swift
//  Todo train
//
//  The clearance is a small reward for coming back, not a fixture on the Hub.
//  It appears only after the app has been in the background for a while.
//  One play spends it. The same return cannot start another.
//

import Foundation

nonisolated struct ApproachClearOffer: Equatable, Sendable {
    /// Long enough that a glance at another app is not a return.
    static let absence: TimeInterval = 30 * 60

    var lastInactiveAt: Date?
    var showing = false
    /// The clock has started, or the player put the panel away.
    var spent = false

    mutating func noteBackground(at now: Date) {
        lastInactiveAt = now
    }

    mutating func noteActive(at now: Date) {
        guard let left = lastInactiveAt else { return }
        let away = now.timeIntervalSince(left)
        lastInactiveAt = now
        guard away >= Self.absence else {
            if spent { showing = false }
            return
        }
        showing = true
        spent = false
    }

    mutating func notePlayStarted() {
        spent = true
    }

    mutating func dismiss() {
        showing = false
        spent = true
    }
}

nonisolated enum ApproachClearOfferStore {
    private static let inactiveKey = "approachClear.offer.inactiveAt"
    private static let showingKey = "approachClear.offer.showing"
    private static let spentKey = "approachClear.offer.spent"

    static func load(_ defaults: UserDefaults = .standard) -> ApproachClearOffer {
        var offer = ApproachClearOffer()
        if defaults.object(forKey: inactiveKey) != nil {
            offer.lastInactiveAt = Date(timeIntervalSince1970: defaults.double(forKey: inactiveKey))
        }
        offer.showing = defaults.bool(forKey: showingKey)
        offer.spent = defaults.bool(forKey: spentKey)
        return offer
    }

    static func save(_ offer: ApproachClearOffer, _ defaults: UserDefaults = .standard) {
        if let date = offer.lastInactiveAt {
            defaults.set(date.timeIntervalSince1970, forKey: inactiveKey)
        } else {
            defaults.removeObject(forKey: inactiveKey)
        }
        defaults.set(offer.showing, forKey: showingKey)
        defaults.set(offer.spent, forKey: spentKey)
    }
}
