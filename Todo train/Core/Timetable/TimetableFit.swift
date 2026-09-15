//
//  TimetableFit.swift
//  Todo train
//
//  Pure look-ahead for ダイヤ: next / current block, mark minutes, folded deadline.
//

import Foundation

nonisolated struct TimetableFitBlock: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var startsAt: Date
    var endsAt: Date

    init(id: UUID = UUID(), title: String, startsAt: Date, endsAt: Date) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
    }
}

nonisolated struct TimetableFitSnapshot: Equatable, Sendable {
    var currentBlock: TimetableFitBlock?
    var nextBlock: TimetableFitBlock?
    /// Floor minutes until the next start. 1...60. Sub-minute (including 30s) is nil.
    var markMinutes: Int?
    /// Earlier of budget end and the next ダイヤ start (not the current overlapping start).
    var nextDeadline: Date?
    var shouldSuppressAway: Bool

    /// The block to show on the 案内板 / Focus / PiP: overlapping first, else next.
    var visibleBlock: TimetableFitBlock? { currentBlock ?? nextBlock }
}

nonisolated enum TimetableFit {
    static let protectionGrace: TimeInterval = 60
    static let awaySuppressionLead: TimeInterval = 120
    static let markWindowMinutes = 60
    static let markFloorSeconds: TimeInterval = 30

    static func markMinutes(until start: Date, now: Date) -> Int? {
        let interval = start.timeIntervalSince(now)
        guard interval >= markFloorSeconds else { return nil }
        let minutes = Int(interval / 60)
        guard (1...markWindowMinutes).contains(minutes) else { return nil }
        return minutes
    }

    static func snapshot(
        blocks: [TimetableFitBlock],
        now: Date,
        budgetEndsAt: Date?
    ) -> TimetableFitSnapshot {
        let active = blocks
            .filter { $0.endsAt > $0.startsAt && now < $0.endsAt }
            .sorted {
                if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
                return $0.id.uuidString < $1.id.uuidString
            }

        let current = active.first { $0.startsAt <= now && now < $0.endsAt }
        let next = active.first { $0.startsAt > now }
        let nextStart = next?.startsAt
        let deadlineCandidates = [budgetEndsAt, nextStart].compactMap { $0 }.filter { $0 > now }
        let nextDeadline = deadlineCandidates.min()
        let suppress = active.contains { block in
            now >= block.startsAt.addingTimeInterval(-awaySuppressionLead) && now < block.endsAt
        }

        return TimetableFitSnapshot(
            currentBlock: current,
            nextBlock: next,
            markMinutes: next.map { markMinutes(until: $0.startsAt, now: now) } ?? nil,
            nextDeadline: nextDeadline,
            shouldSuppressAway: suppress
        )
    }

    static func nextBlockLine(title: String, startsAt: Date, now: Date) -> String {
        if startsAt <= now {
            return title
        }
        return "次 \(title)"
    }
}
