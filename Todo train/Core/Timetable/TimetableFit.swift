//
//  TimetableFit.swift
//  Todo train
//
//  Next ダイヤ vs estimate. Does not block boarding.
//

import Foundation

enum TimetableFit {
    static let protectionGrace: TimeInterval = 60

    struct Block: Equatable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var startsAt: Date
        var endsAt: Date
        var isCancelled: Bool

        var isActive: Bool { !isCancelled && endsAt > startsAt }
    }

    static func activeBlocks(_ blocks: [Block], now: Date) -> [Block] {
        blocks
            .filter { $0.isActive && $0.endsAt > now }
            .sorted { $0.startsAt < $1.startsAt }
    }

    static func nextBlock(in blocks: [Block], now: Date) -> Block? {
        activeBlocks(blocks, now: now).first
    }

    /// Minutes from now to the next block, if it sits on the printed 60-minute track.
    static func markMinutes(now: Date, nextStart: Date?) -> Int? {
        guard let nextStart else { return nil }
        let minutes = Int(nextStart.timeIntervalSince(now) / 60)
        guard minutes >= 1, minutes <= TicketDurationScale.maxMinutes else { return nil }
        return minutes
    }

    static func nextDeadline(budgetEnd: Date?, nextBlockStart: Date?) -> Date? {
        switch (budgetEnd, nextBlockStart) {
        case let (budget?, block?):
            return min(budget, block)
        case let (budget?, nil):
            return budget
        case let (nil, block?):
            return block
        case (nil, nil):
            return nil
        }
    }

    static func protectionBoundary(forStart startsAt: Date) -> Date {
        startsAt.addingTimeInterval(protectionGrace)
    }
}
