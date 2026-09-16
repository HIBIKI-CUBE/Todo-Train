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

/// いま / 掲示 / 次。計器のチップ。
nonisolated enum TimetableOccupancyKind: Equatable, Sendable {
    case occupying
    case notice
    case next

    var prefix: String {
        switch self {
        case .occupying: "いま"
        case .notice: "掲示"
        case .next: "次"
        }
    }
}

nonisolated struct TimetableOccupancyRow: Equatable, Sendable, Identifiable {
    var id: UUID
    var kind: TimetableOccupancyKind
    var clock: String
    var remainingMinutes: Int?
    var title: String
    var spokenLine: String
}

nonisolated struct TimetableOccupancyMark: Equatable, Sendable, Identifiable {
    var id: UUID
    /// 0...1 along the 60-minute rail.
    var position: Double
    /// Remaining occupancy as a band from `position`. Next marks are 0.
    var span: Double
    var isCurrent: Bool
}

/// Occupancy mapped onto a ride's elapsed/budget bar. Nil when the edge is past the ride.
nonisolated struct TimetableProgressOccupancy: Equatable, Sendable {
    var spanStart: Double?
    var spanEnd: Double?
    var mark: Double?

    static let empty = TimetableProgressOccupancy(spanStart: nil, spanEnd: nil, mark: nil)
}

/// Hub / Focus が尺を寄せるか。窓の外なら 60 分のまま。
nonisolated struct TimetableDispatchScale: Equatable, Sendable {
    var zooms: Bool
    /// Seconds from now that map to 1.0 on the instrument.
    var windowSeconds: TimeInterval
    /// Wall-clock occupancy edge the window is aimed at. Nil when quiet.
    var occupancyEdge: Date?

    static let quiet = TimetableDispatchScale(
        zooms: false,
        windowSeconds: TimeInterval(TimetableFit.markWindowMinutes * 60),
        occupancyEdge: nil
    )
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
    /// Slack past 予定/予測 so an occupancy just after arrival still zooms.
    static let dispatchSlack: TimeInterval = 5 * 60
    static let dispatchHeadroom: Double = 1.12
    static let dispatchMinWindow: TimeInterval = 6 * 60

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
    static func occupancyRows(
        fit: TimetableFitSnapshot,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [TimetableOccupancyRow] {
        var rows: [TimetableOccupancyRow] = []
        if let current = fit.currentOccupancy {
            rows.append(
                occupancyRow(
                    kind: current.isAdopted ? .occupying : .notice,
                    occupancy: current,
                    at: current.endsAt,
                    now: now,
                    calendar: calendar
                )
            )
        }
        if let next = fit.nextOccupancy {
            rows.append(
                occupancyRow(
                    kind: .next,
                    occupancy: next,
                    at: next.startsAt,
                    now: now,
                    calendar: calendar
                )
            )
        }
        return rows
    }

    static func occupancyLines(
        fit: TimetableFitSnapshot,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [String] {
        occupancyRows(fit: fit, now: now, calendar: calendar).map(\.spokenLine)
    }

    static func occupancyMarks(
        fit: TimetableFitSnapshot,
        now: Date,
        windowSeconds: TimeInterval = TimeInterval(markWindowMinutes * 60)
    ) -> [TimetableOccupancyMark] {
        let window = max(windowSeconds, 1)
        var marks: [TimetableOccupancyMark] = []
        if let current = fit.currentOccupancy, current.startsAt <= now {
            let remaining = max(0, current.endsAt.timeIntervalSince(now))
            marks.append(
                TimetableOccupancyMark(
                    id: current.id,
                    position: 0,
                    span: max(0, min(1, remaining / window)),
                    isCurrent: true
                )
            )
        }
        if let next = fit.nextOccupancy {
            let offset = next.startsAt.timeIntervalSince(now)
            if offset >= 0, offset <= window {
                marks.append(
                    TimetableOccupancyMark(
                        id: next.id,
                        position: max(0, min(1, offset / window)),
                        span: 0,
                        isCurrent: false
                    )
                )
            }
        }
        return marks
    }

    /// Fraction of a dispatch / 60-minute window. Nil when the offset is past the window.
    static func dispatchFraction(offset: TimeInterval, windowSeconds: TimeInterval) -> Double? {
        guard windowSeconds > 0, offset >= 0 else { return nil }
        let position = offset / windowSeconds
        guard position <= 1 else { return nil }
        return position
    }

    /// Zoom when occupancy sits inside this boarding's arrival window (or occupies now).
    static func boardingDispatch(
        fit: TimetableFitSnapshot,
        now: Date,
        scheduledArrival: Date,
        predictedArrival: Date?
    ) -> TimetableDispatchScale {
        let rideEnd = [scheduledArrival, predictedArrival].compactMap { $0 }.max() ?? scheduledArrival
        let slackEnd = rideEnd.addingTimeInterval(dispatchSlack)
        if let current = fit.currentOccupancy {
            return dispatchWindow(edge: current.endsAt, now: now)
        }
        if let next = fit.nextOccupancy, next.startsAt <= slackEnd {
            return dispatchWindow(edge: next.startsAt, now: now)
        }
        return .quiet
    }

    /// Zoom the ride bar when occupancy is still ahead on elapsed/budget.
    static func rideDispatch(
        occupancy: TimetableProgressOccupancy,
        progress: Double
    ) -> (progress: Double, occupancy: TimetableProgressOccupancy, zooms: Bool) {
        let edge = occupancy.mark ?? occupancy.spanEnd
        guard let edge, edge > progress, edge < 0.92 else {
            return (progress, occupancy, false)
        }
        let domain = max(edge, 0.001)
        var mapped = TimetableProgressOccupancy.empty
        if let start = occupancy.spanStart, let end = occupancy.spanEnd, end > start {
            mapped.spanStart = min(1, max(0, start / domain))
            mapped.spanEnd = min(1, max(0, end / domain))
        }
        if let mark = occupancy.mark {
            mapped.mark = min(1, mark / domain)
        }
        return (min(1, max(0, progress / domain)), mapped, true)
    }

    private static func dispatchWindow(edge: Date, now: Date) -> TimetableDispatchScale {
        let until = max(edge.timeIntervalSince(now), markFloorSeconds)
        let window = min(
            max(until * dispatchHeadroom, dispatchMinWindow),
            TimeInterval(markWindowMinutes * 60)
        )
        return TimetableDispatchScale(zooms: true, windowSeconds: window, occupancyEdge: edge)
    }

    /// Map occupancy onto elapsed/budget. Now sits at `elapsed / budget`; next is wall-clock from there.
    static func occupancyOnProgress(
        fit: TimetableFitSnapshot,
        now: Date,
        elapsed: TimeInterval,
        budget: TimeInterval
    ) -> TimetableProgressOccupancy {
        guard budget > 0 else {
            return TimetableProgressOccupancy(spanStart: nil, spanEnd: nil, mark: nil)
        }
        var spanStart: Double?
        var spanEnd: Double?
        var mark: Double?
        if let current = fit.currentOccupancy {
            let remaining = max(0, current.endsAt.timeIntervalSince(now))
            if let start = progressPosition(elapsed: elapsed, offset: 0, budget: budget) {
                let end = progressPosition(elapsed: elapsed, offset: remaining, budget: budget) ?? 1
                if end > start {
                    spanStart = start
                    spanEnd = end
                }
            }
        }
        if let next = fit.nextOccupancy {
            let until = next.startsAt.timeIntervalSince(now)
            if until >= 0 {
                mark = progressPosition(elapsed: elapsed, offset: until, budget: budget)
            }
        }
        return TimetableProgressOccupancy(spanStart: spanStart, spanEnd: spanEnd, mark: mark)
    }

    private static func progressPosition(
        elapsed: TimeInterval,
        offset: TimeInterval,
        budget: TimeInterval
    ) -> Double? {
        let position = (elapsed + offset) / budget
        guard position >= 0, position <= 1 else { return nil }
        return position
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

    private static func occupancyRow(
        kind: TimetableOccupancyKind,
        occupancy: TimetableOccupancy,
        at date: Date,
        now: Date,
        calendar: Calendar
    ) -> TimetableOccupancyRow {
        let minutes = remainingMinutes(until: date, now: now)
        return TimetableOccupancyRow(
            id: occupancy.id,
            kind: kind,
            clock: clockTime(date, calendar: calendar),
            remainingMinutes: minutes,
            title: occupancy.title,
            spokenLine: occupancyLine(
                prefix: kind.prefix,
                title: occupancy.title,
                at: date,
                now: now,
                calendar: calendar
            )
        )
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
