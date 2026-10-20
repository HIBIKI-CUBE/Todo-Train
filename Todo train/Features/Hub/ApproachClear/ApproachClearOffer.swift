//
//  ApproachClearOffer.swift
//  Todo train
//
//  The clearance is a small reward for coming back, not a fixture on the Hub.
//  It appears after five minutes away, unless that departure was mid-ride.
//  One play spends it. The same return cannot start another.
//

import Foundation

nonisolated struct ApproachClearOffer: Equatable, Sendable {
    /// Away from the app, when the departure was not in the middle of a ride.
    static let absence: TimeInterval = 5 * 60

    var lastInactiveAt: Date?
    /// The background that `lastInactiveAt` marks began during a running task.
    var leftDuringTask = false
    var showing = false
    /// The clock has started, or the player put the panel away.
    var spent = false

    mutating func noteBackground(at now: Date, taskRunning: Bool = false) {
        lastInactiveAt = now
        leftDuringTask = taskRunning
    }

    mutating func noteActive(at now: Date) {
        guard let left = lastInactiveAt else { return }
        let away = now.timeIntervalSince(left)
        let excluded = leftDuringTask
        lastInactiveAt = now
        leftDuringTask = false
        guard !excluded, away >= Self.absence else {
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

/// When the Hub mounts the clearance. Force is a developer-menu override.
nonisolated enum ApproachClearVisibility {
    static func presented(
        offerShowing: Bool,
        developerToolsUnlocked: Bool,
        forceVisible: Bool,
        passengerClaimsScreen: Bool = false
    ) -> Bool {
        if passengerClaimsScreen { return false }
        return offerShowing || (developerToolsUnlocked && forceVisible)
    }
}

nonisolated enum ApproachClearOfferStore {
    private static let inactiveKey = "approachClear.offer.inactiveAt"
    private static let leftDuringTaskKey = "approachClear.offer.leftDuringTask"
    private static let showingKey = "approachClear.offer.showing"
    private static let spentKey = "approachClear.offer.spent"

    static func load(_ defaults: UserDefaults = .standard) -> ApproachClearOffer {
        var offer = ApproachClearOffer()
        if defaults.object(forKey: inactiveKey) != nil {
            offer.lastInactiveAt = Date(timeIntervalSince1970: defaults.double(forKey: inactiveKey))
        }
        offer.leftDuringTask = defaults.bool(forKey: leftDuringTaskKey)
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
        defaults.set(offer.leftDuringTask, forKey: leftDuringTaskKey)
        defaults.set(offer.showing, forKey: showingKey)
        defaults.set(offer.spent, forKey: spentKey)
    }
}
