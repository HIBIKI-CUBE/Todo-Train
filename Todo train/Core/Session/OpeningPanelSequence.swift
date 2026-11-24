//
//  OpeningPanelSequence.swift
//  Todo train
//
//  SEQ の仕分け。順番は本人が決め、線は収まる確率 0.9 の位置だけを示す。
//  題名はこの型に載せない。記録へ出すのも id と置き場所と答えだけ。
//

import Foundation

enum OpeningPanelSequencePile: String, Codable, CaseIterable, Sendable {
    case today
    case ifPossible
    case later
}

struct OpeningPanelSequenceStat: Equatable, Sendable, Identifiable {
    var id: UUID
    var estimateMinutes: Int
    var similarCount: Int
    var similarMedianMinutes: Int
    var similarSpreadMinutes: Double
    var daysBelowLine: Int
    var dueDate: Date?
}

struct OpeningPanelSequencePlacement: Equatable, Codable, Sendable {
    var ticketID: UUID
    var pile: OpeningPanelSequencePile
    var aboveLine: Bool
}

struct OpeningPanelSequenceAnswer: Equatable, Codable, Sendable {
    /// sort / undoSort / compare / undoCompare
    var kind: String
    var ticketID: UUID
    var pile: OpeningPanelSequencePile?
    var otherTicketID: UUID?
    var insertedFirst: Bool?
}

struct OpeningPanelSequenceDayMark: Equatable, Sendable {
    var ticketID: UUID
    var consecutiveDays: Int
    var lastBelowDay: Date?
}

enum OpeningPanelSequenceMath {
    /// 標準正規の 90% 点。モックの Z。
    static let z90 = 1.2816

    static func meanMinutes(_ stat: OpeningPanelSequenceStat) -> Double {
        if stat.similarCount >= EstimateHeuristic.minimumSampleCount {
            return Double(stat.similarMedianMinutes)
        }
        return Double(stat.estimateMinutes)
    }

    /// 似た乗車が 3 件以上ならその標準偏差（分）。なければ見積もりの 30%。
    static func sigmaMinutes(_ stat: OpeningPanelSequenceStat) -> Double {
        if stat.similarCount >= EstimateHeuristic.minimumSampleCount {
            return max(0, stat.similarSpreadMinutes)
        }
        return 0.3 * Double(stat.estimateMinutes)
    }

    /// 標本の標準偏差（分）。母分散で割る。3 件未満は 0。
    static func spreadMinutes(_ samples: [TimeInterval]) -> Double {
        guard samples.count >= EstimateHeuristic.minimumSampleCount else { return 0 }
        let minutes = samples.map { $0 / 60 }
        let mean = minutes.reduce(0, +) / Double(minutes.count)
        let variance = minutes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(minutes.count)
        return variance.squareRoot()
    }

    /// μ + 1.28σ が空き時間以下であり続ける、最後の位置。
    static func lineIndex(order: [OpeningPanelSequenceStat], freeMinutes: Double) -> Int {
        var sum = 0.0
        var variance = 0.0
        var line = 0
        for (offset, stat) in order.enumerated() {
            sum += meanMinutes(stat)
            let sigma = sigmaMinutes(stat)
            variance += sigma * sigma
            if sum + z90 * variance.squareRoot() <= freeMinutes {
                line = offset + 1
            } else {
                break
            }
        }
        return line
    }

    /// 窓に並ぶ切符の行は最大 7 行。8 行目は「ほか N 枚」の行で、盤の大きさは変わらない。
    static let maxShownRows = 7

    /// 線の下は最大 3 枚。全体は `maxShownRows` まで。それより奥はまとめ表示。
    static func visibleSpan(line: Int, total: Int) -> (shown: Int, hidden: Int) {
        guard total > 0 else { return (0, 0) }
        let below = max(1, min(3, maxShownRows - line))
        let shown = min(total, line + below, maxShownRows)
        return (shown, total - shown)
    }
}

enum OpeningPanelSequenceDays {
    static func advance(
        previous: [OpeningPanelSequenceDayMark],
        placements: [OpeningPanelSequencePlacement],
        day: Date,
        calendar: Calendar
    ) -> [OpeningPanelSequenceDayMark] {
        var byID = Dictionary(uniqueKeysWithValues: previous.map { ($0.ticketID, $0) })
        let start = calendar.startOfDay(for: day)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)
        for placement in placements {
            if placement.aboveLine {
                byID[placement.ticketID] = OpeningPanelSequenceDayMark(
                    ticketID: placement.ticketID,
                    consecutiveDays: 0,
                    lastBelowDay: nil
                )
                continue
            }
            let prior = byID[placement.ticketID]
            let days: Int
            if let last = prior?.lastBelowDay, calendar.isDate(last, inSameDayAs: start) {
                days = max(prior?.consecutiveDays ?? 1, 1)
            } else if let last = prior?.lastBelowDay,
                      let yesterday,
                      calendar.isDate(last, inSameDayAs: yesterday) {
                days = (prior?.consecutiveDays ?? 0) + 1
            } else {
                days = 1
            }
            byID[placement.ticketID] = OpeningPanelSequenceDayMark(
                ticketID: placement.ticketID,
                consecutiveDays: days,
                lastBelowDay: start
            )
        }
        var seen: Set<UUID> = []
        var ordered: [OpeningPanelSequenceDayMark] = []
        for mark in previous where seen.insert(mark.ticketID).inserted {
            if let updated = byID[mark.ticketID] {
                ordered.append(updated)
            }
        }
        let extras = byID.keys
            .filter { !seen.contains($0) }
            .sorted { $0.uuidString < $1.uuidString }
        for id in extras {
            if let mark = byID[id] {
                ordered.append(mark)
            }
        }
        return ordered
    }
}

struct OpeningPanelSequenceRNG: Equatable {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        state = state &+ 0x6D2B79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        let mixed = (t ^ (t >> 7)) &* (61 | t)
        t = (t &+ mixed) ^ t
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

struct OpeningPanelSequenceEngine: Equatable {
    enum Phase: Equatable, Sendable {
        case sorting
        case comparing
        case result
    }

    private struct Insertion: Equatable {
        var sorted: [Int]
        var current: Int
        var rest: [Int]
        var lo: Int
        var hi: Int

        var mid: Int { (lo + hi) / 2 }
    }

    private struct CompareMark: Equatable {
        var insertion: Insertion
        var insertedID: UUID
        var otherID: UUID
        var insertedFirst: Bool
    }

    private struct SortMark: Equatable {
        var ticket: Int
        var pile: Int
    }

    private(set) var phase: Phase = .sorting
    private(set) var queue: [Int] = []
    private(set) var progress: Double = 0
    private(set) var comparisons: Int = 0
    private(set) var answers: [OpeningPanelSequenceAnswer] = []
    private(set) var sortedCount: Int = 0

    private var stats: [OpeningPanelSequenceStat]
    private var groups: [[Int]]
    private var piles: [Int: OpeningPanelSequencePile] = [:]
    private var parts: [[Int]] = [[], [], []]
    private var sortHistory: [SortMark] = []
    private var progressBase: Double = 0
    private var progressSpan: Double = 0.85
    private var rounds = 0
    private var target = -1
    private var insertion: Insertion?
    private var compareHistory: [CompareMark] = []
    private var rng: OpeningPanelSequenceRNG
    let freeMinutes: Double

    static func start(
        stats: [OpeningPanelSequenceStat],
        freeMinutes: Double,
        seed: UInt32 = 1,
        queue ids: [UUID]? = nil
    ) -> OpeningPanelSequenceEngine? {
        guard !stats.isEmpty else { return nil }
        var engine = OpeningPanelSequenceEngine(
            stats: stats,
            groups: [Array(stats.indices)],
            rng: OpeningPanelSequenceRNG(seed: seed),
            freeMinutes: max(0, freeMinutes)
        )
        let order: [Int]
        if let ids {
            let lookup = Dictionary(uniqueKeysWithValues: stats.enumerated().map { ($1.id, $0) })
            let mapped = ids.compactMap { lookup[$0] }
            guard mapped.count == stats.count, Set(mapped).count == stats.count else { return nil }
            order = mapped
        } else {
            order = engine.shuffled(Array(stats.indices))
        }
        engine.queue = order
        engine.progressBase = 0
        engine.progressSpan = 0.85
        return engine
    }

    var queueIDs: [UUID] { queue.map { stats[$0].id } }

    var orderIDs: [UUID] { groups.flatMap { $0 }.map { stats[$0].id } }

    var lineIndex: Int {
        OpeningPanelSequenceMath.lineIndex(order: orderedStats, freeMinutes: freeMinutes)
    }

    var canUndo: Bool {
        switch phase {
        case .sorting: return !sortHistory.isEmpty
        case .comparing: return !compareHistory.isEmpty
        case .result: return false
        }
    }

    var keyEnabled: [Bool] {
        switch phase {
        case .sorting: return [true, true, true]
        case .comparing: return [true, true, false]
        case .result: return [false, false, false]
        }
    }

    var pileCounts: [Int] { parts.map(\.count) }

    func stat(_ id: UUID) -> OpeningPanelSequenceStat? {
        stats.first { $0.id == id }
    }

    func stat(at index: Int) -> OpeningPanelSequenceStat? {
        stats.indices.contains(index) ? stats[index] : nil
    }

    var frontIndex: Int? { queue.first }

    var waitingIndices: [Int] { Array(queue.dropFirst().prefix(3)) }

    var showsEndOfQueue: Bool { phase == .sorting && !queue.isEmpty && queue.count <= 4 }

    var comparison: (inserted: Int, other: Int, upcoming: [Int])? {
        guard phase == .comparing, let insertion else { return nil }
        let other = insertion.sorted[insertion.mid]
        return (insertion.current, other, insertion.rest)
    }

    var placements: [OpeningPanelSequencePlacement] {
        let order = groups.flatMap { $0 }
        let line = OpeningPanelSequenceMath.lineIndex(order: order.map { stats[$0] }, freeMinutes: freeMinutes)
        return order.enumerated().compactMap { offset, index in
            guard let pile = piles[index] else { return nil }
            return OpeningPanelSequencePlacement(
                ticketID: stats[index].id,
                pile: pile,
                aboveLine: offset < line
            )
        }
    }

    var sortingTotal: Int { sortedCount + queue.count }

    mutating func choosePile(_ index: Int) -> Bool {
        guard phase == .sorting, !queue.isEmpty, parts.indices.contains(index) else { return false }
        let ticket = queue.removeFirst()
        parts[index].append(ticket)
        sortHistory.append(SortMark(ticket: ticket, pile: index))
        sortedCount += 1
        let pile = OpeningPanelSequencePile.allCases[index]
        piles[ticket] = pile
        answers.append(
            OpeningPanelSequenceAnswer(
                kind: "sort",
                ticketID: stats[ticket].id,
                pile: pile,
                otherTicketID: nil,
                insertedFirst: nil
            )
        )
        noteSortProgress()
        if queue.isEmpty {
            finishSortingRound()
        }
        return true
    }

    mutating func chooseInsertedFirst(_ insertedFirst: Bool) -> Bool {
        guard phase == .comparing, var step = insertion else { return false }
        let otherIndex = step.sorted[step.mid]
        let insertedIndex = step.current
        compareHistory.append(
            CompareMark(
                insertion: step,
                insertedID: stats[insertedIndex].id,
                otherID: stats[otherIndex].id,
                insertedFirst: insertedFirst
            )
        )
        answers.append(
            OpeningPanelSequenceAnswer(
                kind: "compare",
                ticketID: stats[insertedIndex].id,
                pile: nil,
                otherTicketID: stats[otherIndex].id,
                insertedFirst: insertedFirst
            )
        )
        let mid = step.mid
        if insertedFirst {
            step.hi = mid
        } else {
            step.lo = mid + 1
        }
        comparisons += 1
        if step.lo >= step.hi {
            step.sorted.insert(step.current, at: step.lo)
            if step.rest.isEmpty {
                groups.replaceSubrange(target...target, with: step.sorted.map { [$0] })
                insertion = nil
                compareHistory = []
                let cut = cutGroup()
                rounds += 1
                if let cut, rounds < 4 {
                    target = cut
                    startInsertion(groups[cut])
                } else {
                    phase = .result
                    insertion = nil
                    progress = 1
                }
                return true
            }
            step.current = step.rest.removeFirst()
            step.lo = 0
            step.hi = step.sorted.count
        }
        insertion = step
        noteCompareProgress(step)
        return true
    }

    mutating func undo() -> Bool {
        switch phase {
        case .sorting:
            guard let last = sortHistory.popLast() else { return false }
            let ticket = last.ticket
            let pileIndex = last.pile
            if let position = parts[pileIndex].lastIndex(of: ticket) {
                parts[pileIndex].remove(at: position)
            }
            queue.insert(ticket, at: 0)
            sortedCount = max(0, sortedCount - 1)
            piles[ticket] = nil
            answers.append(
                OpeningPanelSequenceAnswer(
                    kind: "undoSort",
                    ticketID: stats[ticket].id,
                    pile: OpeningPanelSequencePile.allCases[pileIndex],
                    otherTicketID: nil,
                    insertedFirst: nil
                )
            )
            return true
        case .comparing:
            guard let mark = compareHistory.popLast() else { return false }
            insertion = mark.insertion
            comparisons = max(0, comparisons - 1)
            answers.append(
                OpeningPanelSequenceAnswer(
                    kind: "undoCompare",
                    ticketID: mark.insertedID,
                    pile: nil,
                    otherTicketID: mark.otherID,
                    insertedFirst: mark.insertedFirst
                )
            )
            return true
        case .result:
            return false
        }
    }

    mutating func finishEarly() {
        guard phase != .result else { return }
        if phase == .sorting {
            let classified = parts.filter { !$0.isEmpty }
            let rest = queue.isEmpty ? [] : [queue]
            groups = classified + rest
            queue = []
        }
        phase = .result
        insertion = nil
    }

    private var orderedStats: [OpeningPanelSequenceStat] {
        groups.flatMap { $0 }.map { stats[$0] }
    }

    private mutating func shuffled(_ items: [Int]) -> [Int] {
        var copy = items
        guard copy.count > 1 else { return copy }
        for index in stride(from: copy.count - 1, through: 1, by: -1) {
            let slot = Int((rng.nextUnit() * Double(index + 1)).rounded(.down))
            copy.swapAt(index, slot)
        }
        return copy
    }

    private mutating func noteSortProgress() {
        let denom = sortedCount + queue.count
        guard denom > 0 else { return }
        let candidate = progressBase + progressSpan * Double(sortedCount) / Double(denom)
        progress = max(progress, candidate)
    }

    private mutating func noteCompareProgress(_ step: Insertion) {
        let left = remainingComparisons(step)
        let denom = comparisons + left
        guard denom > 0 else { return }
        let candidate = progressBase + progressSpan * Double(comparisons) / Double(denom)
        progress = max(progress, candidate)
    }

    private mutating func finishSortingRound() {
        groups = parts.filter { !$0.isEmpty }
        let cut = cutGroup()
        rounds += 1
        if let cut, rounds < 4 {
            target = cut
            startInsertion(groups[cut])
        } else {
            phase = .result
            progress = 1
        }
    }

    private mutating func startInsertion(_ items: [Int]) {
        guard items.count > 1 else {
            phase = .result
            progress = 1
            return
        }
        phase = .comparing
        insertion = Insertion(
            sorted: [items[0]],
            current: items[1],
            rest: Array(items.dropFirst(2)),
            lo: 0,
            hi: 1
        )
        compareHistory = []
        comparisons = 0
        progressBase = progress
        progressSpan = (1 - progressBase) * 0.9
    }

    private func cutGroup() -> Int? {
        let order = groups.flatMap { $0 }
        let line = OpeningPanelSequenceMath.lineIndex(
            order: order.map { stats[$0] },
            freeMinutes: freeMinutes
        )
        var start = 0
        for (group, items) in groups.enumerated() {
            let end = start + items.count
            if line > start, line < end, items.count > 1 {
                return group
            }
            start = end
        }
        return nil
    }

    private func remainingComparisons(_ step: Insertion) -> Int {
        func span(_ count: Int) -> Int {
            guard count > 0 else { return 0 }
            return Int(ceil(log2(Double(count + 1))))
        }
        var remaining = span(step.hi - step.lo)
        var width = step.sorted.count + 1
        for _ in step.rest {
            remaining += span(width)
            width += 1
        }
        return remaining
    }
}

extension OpeningPanelSequenceStat {
    static func make(
        ticket: Ticket,
        sessions: [WorkSession],
        now: Date,
        calendar: Calendar,
        daysBelow: Int
    ) -> OpeningPanelSequenceStat {
        let selection = RideSimilarity.select(
            title: ticket.title,
            tagIDs: BoardingForecast.tagFilter(for: ticket) ?? [],
            ticket: ticket,
            sessions: sessions,
            now: now,
            calendar: calendar
        )
        let samples = selection.chosen.map(\.ride.activeSeconds)
        let predicted = BoardingForecast.predictedDuration(from: samples)
        let estimate = max(ticket.estimatedSeconds / 60, 1)
        return OpeningPanelSequenceStat(
            id: ticket.id,
            estimateMinutes: estimate,
            similarCount: samples.count,
            similarMedianMinutes: predicted?.minutes ?? 0,
            similarSpreadMinutes: OpeningPanelSequenceMath.spreadMinutes(samples),
            daysBelowLine: daysBelow,
            dueDate: ticket.dueDate
        )
    }
}

enum OpeningPanelSequenceArchive {
    static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
