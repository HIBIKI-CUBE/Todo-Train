//
//  TimetableGuardLogic.swift
//  Todo train
//
//  Pure ATS: notify at ダイヤ start, pause at start+60s. No ATO.
//

import Foundation

enum TimetableGuardLogic {
    struct Ride: Equatable, Sendable {
        var sessionID: UUID
        var startedAt: Date
        var segmentStartedAt: Date?
        var isOpen: Bool
        var isPaused: Bool
        var endedAt: Date?

        var isRunning: Bool { isOpen && !isPaused && endedAt == nil }

        var activeSegmentStart: Date { segmentStartedAt ?? startedAt }
    }

    struct StoredGuard: Equatable, Sendable {
        var id: UUID
        var sessionID: UUID
        var blockID: UUID
        var notifiedAt: Date
        var protectionBoundary: Date
        var resolvedAt: Date?
        var invalidatedAt: Date?

        var isOpen: Bool { resolvedAt == nil && invalidatedAt == nil }
    }

    enum Effect: Equatable, Sendable {
        case none
        case arm(blockID: UUID, notifiedAt: Date, protectionBoundary: Date)
        case pause(at: Date, guardID: UUID?, blockID: UUID)
        case resolve(guardID: UUID)
        case invalidate(guardID: UUID)
    }

    static func effects(
        ride: Ride?,
        blocks: [TimetableFit.Block],
        guards: [StoredGuard],
        now: Date
    ) -> [Effect] {
        let openGuards = guards.filter(\.isOpen)

        guard let ride else {
            return openGuards.map { .invalidate(guardID: $0.id) }
        }

        if !ride.isOpen || ride.endedAt != nil {
            return openGuards.map { .invalidate(guardID: $0.id) }
        }

        if ride.isPaused {
            return openGuards.map { .resolve(guardID: $0.id) }
        }

        guard ride.isRunning else { return [] }

        if let overlapping = overlappingEligibleBlock(ride: ride, blocks: blocks, now: now) {
            let boundary = TimetableFit.protectionBoundary(forStart: overlapping.startsAt)
            let existing = openGuards.first { $0.blockID == overlapping.id && $0.sessionID == ride.sessionID }
            if now >= boundary {
                return [.pause(at: pauseInstant(boundary: boundary, segmentStart: ride.activeSegmentStart), guardID: existing?.id, blockID: overlapping.id)]
            }
            if existing == nil {
                return [.arm(blockID: overlapping.id, notifiedAt: overlapping.startsAt, protectionBoundary: boundary)]
            }
            return []
        }

        return []
    }

    /// The block this running segment must yield to: started after the segment began, and has already started.
    static func overlappingEligibleBlock(
        ride: Ride,
        blocks: [TimetableFit.Block],
        now: Date
    ) -> TimetableFit.Block? {
        blocks
            .filter { $0.isActive }
            .filter { ride.activeSegmentStart < $0.startsAt }
            .filter { $0.startsAt <= now }
            .sorted { $0.startsAt < $1.startsAt }
            .first
    }

    static func upcomingEligibleBlock(
        ride: Ride,
        blocks: [TimetableFit.Block],
        now: Date
    ) -> TimetableFit.Block? {
        blocks
            .filter { $0.isActive }
            .filter { ride.activeSegmentStart < $0.startsAt }
            .filter { $0.startsAt > now && $0.endsAt > now }
            .sorted { $0.startsAt < $1.startsAt }
            .first
    }

    static func pauseInstant(boundary: Date, segmentStart: Date) -> Date {
        max(boundary, segmentStart)
    }

    static func shouldSuppressAway(blocks: [TimetableFit.Block], now: Date) -> Bool {
        let lead = TimeInterval(2 * 60)
        return blocks.contains { block in
            guard block.isActive else { return false }
            return now >= block.startsAt.addingTimeInterval(-lead) && now < block.endsAt
        }
    }
}
