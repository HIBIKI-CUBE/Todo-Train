//
//  TimetableFit.swift
//  Todo train
//
//  Pure look-ahead for ダイヤ: next / current block, mark minutes, folded deadline.
//  計器。指図しない。占有はダイヤと掲示を混ぜ、載っている方が勝つ。
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

/// いま / 次の占有。乗る対象ではない。計器の材料。
nonisolated struct TimetableOccupancy: Equatable, Sendable, Identifiable {
    var block: TimetableFitBlock
    var isAdopted: Bool

    var id: UUID { block.id }
    var title: String { block.title }
    var startsAt: Date { block.startsAt }
    var endsAt: Date { block.endsAt }
}

nonisolated struct TimetableFitSnapshot: Equatable, Sendable {
    var currentBlock: TimetableFitBlock?
    var nextBlock: TimetableFitBlock?
    var currentOccupancy: TimetableOccupancy?
    var nextOccupancy: TimetableOccupancy?
    /// Floor minutes until the next occupancy start. 1...60. Sub-minute (including 30s) is nil.
    var markMinutes: Int?
    /// Floor minutes until the current occupancy ends. Same window as markMinutes.
    var remainingMinutes: Int?
    /// Earlier of budget end and the next ダイヤ start (not the current overlapping start).
    var nextDeadline: Date?
    var shouldSuppressAway: Bool

    /// The occupancy to show on a one-line instrument: overlapping first, else next.
    var visibleOccupancy: TimetableOccupancy? { currentOccupancy ?? nextOccupancy }

    /// The adopted block to show when occupancy is not needed. Overlapping first, else next.
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

    /// Stable id for a live 掲示 so 案内板 marks do not churn every render.
    static func noticeBlockID(_ raw: String) -> UUID {
        var digest = [UInt8](repeating: 0, count: 16)
        let bytes = Array(raw.utf8)
        for (index, byte) in bytes.enumerated() {
            digest[index % 16] ^= byte
            digest[(index &+ 7) % 16] &+= byte &* 31
        }
        digest[6] = (digest[6] & 0x0F) | 0x40
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    static func snapshot(
        blocks: [TimetableFitBlock],
        notices: [TimetableFitBlock] = [],
        now: Date,
        budgetEndsAt: Date?
    ) -> TimetableFitSnapshot {
        let active = sortedValid(blocks, now: now)
        let liveNotices = sortedValid(notices, now: now)

        let current = active.first { $0.startsAt <= now && now < $0.endsAt }
        let next = active.first { $0.startsAt > now }
        let occupancy = occupancies(adopted: active, notices: liveNotices, now: now)
        let nextStart = next?.startsAt
        let deadlineCandidates = [budgetEndsAt, nextStart].compactMap { $0 }.filter { $0 > now }
        let nextDeadline = deadlineCandidates.min()
        let suppressAdopted = active.contains { block in
            now >= block.startsAt.addingTimeInterval(-awaySuppressionLead) && now < block.endsAt
        }
        let suppressNotice = liveNotices.contains { notice in
            notice.startsAt <= now && now < notice.endsAt
        }

        return TimetableFitSnapshot(
            currentBlock: current,
            nextBlock: next,
            currentOccupancy: occupancy.current,
            nextOccupancy: occupancy.next,
            markMinutes: occupancy.next.map { markMinutes(until: $0.startsAt, now: now) } ?? nil,
            remainingMinutes: occupancy.current.map { markMinutes(until: $0.endsAt, now: now) } ?? nil,
            nextDeadline: nextDeadline,
            shouldSuppressAway: suppressAdopted || suppressNotice
        )
    }

    /// Adopted overlapping wins. Next is the earliest remaining start among adopted and notices.
    static func occupancies(
        adopted: [TimetableFitBlock],
        notices: [TimetableFitBlock],
        now: Date
    ) -> (current: TimetableOccupancy?, next: TimetableOccupancy?) {
        let adoptedCurrent = sortedValid(adopted, now: now)
            .first { $0.startsAt <= now && now < $0.endsAt }
        let noticeCurrent = sortedValid(notices, now: now)
            .first { $0.startsAt <= now && now < $0.endsAt }

        let current: TimetableOccupancy?
        if let adoptedCurrent {
            current = TimetableOccupancy(block: adoptedCurrent, isAdopted: true)
        } else if let noticeCurrent {
            current = TimetableOccupancy(block: noticeCurrent, isAdopted: false)
        } else {
            current = nil
        }

        let upcoming =
            sortedValid(adopted, now: now)
            .filter { $0.startsAt > now }
            .map { TimetableOccupancy(block: $0, isAdopted: true) }
            + sortedValid(notices, now: now)
            .filter { $0.startsAt > now }
            .map { TimetableOccupancy(block: $0, isAdopted: false) }

        let next = upcoming.sorted { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            if lhs.isAdopted != rhs.isAdopted { return lhs.isAdopted }
            return lhs.id.uuidString < rhs.id.uuidString
        }.first

        return (current, next)
    }

    static func occupyingLine(
        title: String,
        endsAt: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        occupancyLine(prefix: "いま", title: title, at: endsAt, now: now, calendar: calendar)
    }

    static func nextBlockLine(
        title: String,
        startsAt: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        if startsAt <= now {
            return title
        }
        return occupancyLine(prefix: "次", title: title, at: startsAt, now: now, calendar: calendar)
    }

    static func noticeLine(
        title: String,
        endsAt: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        occupancyLine(prefix: "掲示", title: title, at: endsAt, now: now, calendar: calendar)
    }

    /// One instrument line. Occupying now first, else next.
    static func dutyLine(
        fit: TimetableFitSnapshot,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        if let current = fit.currentOccupancy {
            if current.isAdopted {
                return occupyingLine(title: current.title, endsAt: current.endsAt, now: now, calendar: calendar)
            }
            return noticeLine(title: current.title, endsAt: current.endsAt, now: now, calendar: calendar)
        }
        if let next = fit.nextOccupancy {
            return nextBlockLine(title: next.title, startsAt: next.startsAt, now: now, calendar: calendar)
        }
        return nil
    }

    /// Second instrument line. Only when something occupies now and something follows.
    static func nextDutyLine(
        fit: TimetableFitSnapshot,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard fit.currentOccupancy != nil, let next = fit.nextOccupancy else { return nil }
        return nextBlockLine(title: next.title, startsAt: next.startsAt, now: now, calendar: calendar)
    }

    /// Hub / Focus / 案内板. At most now + next.
    static func occupancyLines(
        fit: TimetableFitSnapshot,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [String] {
        [
            dutyLine(fit: fit, now: now, calendar: calendar),
            nextDutyLine(fit: fit, now: now, calendar: calendar)
        ].compactMap { $0 }
    }

    /// Clock of a occupancy edge. Tests pass a UTC calendar so the string stays stable.
    static func clockTime(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }

    /// Floor minutes until a occupancy edge. 30s floor. No 60 cap — the plate still uses markMinutes.
    static func remainingMinutes(until date: Date, now: Date) -> Int? {
        let interval = date.timeIntervalSince(now)
        guard interval >= markFloorSeconds else { return nil }
        let minutes = Int(interval / 60)
        guard minutes >= 1 else { return nil }
        return minutes
    }

    private static func occupancyLine(
        prefix: String,
        title: String,
        at date: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        let clock = clockTime(date, calendar: calendar)
        if let minutes = remainingMinutes(until: date, now: now) {
            return "\(prefix) \(clock) \(minutes)分 \(title)"
        }
        return "\(prefix) \(clock) \(title)"
    }

    private static func sortedValid(_ blocks: [TimetableFitBlock], now: Date) -> [TimetableFitBlock] {
        blocks
            .filter { $0.endsAt > $0.startsAt && now < $0.endsAt }
            .sorted {
                if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
}
