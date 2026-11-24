//
//  TicketsModule.swift
//  Todo train
//
//  切符の窓。待機中の行は番号の枠・題名・切れ目・日数・見積もり/実績。
//  右の 3 つのキーと見出しの窓は格子が描く。並びと TODAY の区切りは盤を落としても残す。
//

import SwiftData
import SwiftUI

enum OpeningPanelTicketMetrics {
    /// `.tr` の高さ。枠線を含む。
    static let rowHeight: CGFloat = 12.2
    static let rowGap: CGFloat = 4
    static let titleSize: CGFloat = 10
    static let pairSize: CGFloat = 9
    static let rankWidth: CGFloat = 13
    static let rankHeight: CGFloat = 10
    /// 計算中の前回の値。先発の行が使う。
    static let staleDurationOpacity: Double = 0.35
    static let contentTop: CGFloat = 2
    static let contentHorizontal: CGFloat = 5
    static let belowRowOpacity: Double = 0.55
    static let pairOpacity: Double = 0.8
    static let slashOpacity: Double = 0.55
    static let badgeOpacity: Double = 0.9
    static let fullWidthMinutes = 120
    static let defaultCut = 3
    static let rowLine = Color(red: 34 / 255, green: 34 / 255, blue: 34 / 255)
    static let rankInk = Color(red: 21 / 255, green: 22 / 255, blue: 23 / 255)
    /// SEQ のレンズは `.k` の brightness(1.16) の内側。
    static var sequenceLitInk: Color {
        Color(red: 1, green: min(1, 176 / 255 * 1.16), blue: 0, opacity: 0.85)
    }
}

struct OpeningPanelTicketRow: Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var estimateMinutes: Int
    var actualMinutes: Int
    var similarCount: Int = 0
    var similarMedianMinutes: Int = 0
    var daysBelow: Int = 0
    var arrival: OpeningPanelArrivalPlace = .empty
}

struct OpeningPanelTicketPair: Equatable, Sendable {
    var estimate: String
    var median: String
}

struct OpeningPanelPileKeyState: Equatable, Identifiable, Sendable {
    var id: Int
    var title: String
    var count: String
    var lit: Bool

    static let idle: [OpeningPanelPileKeyState] = [
        OpeningPanelPileKeyState(id: 0, title: "今日", count: "", lit: false),
        OpeningPanelPileKeyState(id: 1, title: "できれば", count: "", lit: false),
        OpeningPanelPileKeyState(id: 2, title: "あとで", count: "", lit: false),
    ]
}

struct OpeningPanelDurationPresentation: Equatable, Sendable {
    var text: String
    var faint: Bool
}

enum OpeningPanelTicketTouch: Equatable {
    case reject
    case ignore
    case placeCut(Int)
    case cutStays
}

enum OpeningPanelTickets {
    static func rows(
        from tickets: [Ticket],
        sessions: [WorkSession],
        now: Date = .now,
        calendar: Calendar = .current,
        refinedMinutes: (Ticket) -> Int? = { _ in nil }
    ) -> [OpeningPanelTicketRow] {
        tickets
            .filter(\.isOpen)
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ticket in
                let snapshot = BoardingForecast.make(
                    now: now,
                    ticket: ticket,
                    sessions: sessions,
                    calendar: calendar
                )
                let resolved = resolveMinutes(
                    estimatedSeconds: ticket.estimatedSeconds,
                    medianMinutes: snapshot.predictedMinutes,
                    refined: refinedMinutes(ticket)
                )
                let similar = similarRide(ticket: ticket, sessions: sessions, now: now, calendar: calendar)
                return OpeningPanelTicketRow(
                    id: ticket.id,
                    title: ticket.title,
                    estimateMinutes: resolved.estimate,
                    actualMinutes: resolved.actual,
                    similarCount: similar.count,
                    similarMedianMinutes: similar.medianMinutes,
                    arrival: .current(resolved.actual)
                )
            }
    }

    /// 見積もりは切符の長さ。実際は予測の中央値で、ArrivalForecast の補正があればそちら。
    static func resolveMinutes(
        estimatedSeconds: Int,
        medianMinutes: Int?,
        refined: Int?
    ) -> (estimate: Int, actual: Int) {
        let estimate = max(estimatedSeconds / 60, 1)
        let actual = max(refined ?? medianMinutes ?? estimate, 1)
        return (estimate, actual)
    }

    static func resolveMinutes(
        estimatedSeconds: Int,
        samples: [TimeInterval],
        refined: Int?
    ) -> (estimate: Int, actual: Int) {
        resolveMinutes(
            estimatedSeconds: estimatedSeconds,
            medianMinutes: BoardingForecast.predictedDuration(from: samples)?.minutes,
            refined: refined
        )
    }

    static func rows(
        from tickets: [Ticket],
        arrivals: [UUID: OpeningPanelArrivalPlace],
        sessions: [WorkSession] = [],
        daysBelow: [UUID: Int] = [:],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [OpeningPanelTicketRow] {
        tickets
            .filter(\.isOpen)
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ticket in
                let estimate = max(ticket.estimatedSeconds / 60, 1)
                let place = arrivals[ticket.id] ?? .empty
                let similar = similarRide(ticket: ticket, sessions: sessions, now: now, calendar: calendar)
                return OpeningPanelTicketRow(
                    id: ticket.id,
                    title: ticket.title,
                    estimateMinutes: estimate,
                    actualMinutes: place.minutes ?? estimate,
                    similarCount: similar.count,
                    similarMedianMinutes: similar.medianMinutes,
                    daysBelow: daysBelow[ticket.id] ?? 0,
                    arrival: place
                )
            }
    }

    static func durationPresentation(
        arrival: OpeningPanelArrivalPlace,
        estimate: Int,
        growthStep: Int
    ) -> OpeningPanelDurationPresentation {
        let minutes: Int
        let faint: Bool
        switch arrival {
        case .empty:
            return OpeningPanelDurationPresentation(text: "", faint: false)
        case .previous(let value):
            minutes = value
            faint = true
        case .current(let value):
            minutes = value
            faint = false
        }
        let shown = shownMinutes(estimate: estimate, actual: minutes, step: growthStep)
        return OpeningPanelDurationPresentation(
            text: durationText(minutes: shown),
            faint: faint
        )
    }

    static func initialCut(count: Int) -> Int {
        min(OpeningPanelTicketMetrics.defaultCut, max(count, 0))
    }

    static func shownMinutes(estimate: Int, actual: Int, step: Int) -> Int {
        let clamped = min(max(step, 0), OpeningPanelTiming.ticketGrowthSteps)
        let delta = Double(actual - estimate) * Double(clamped) / Double(OpeningPanelTiming.ticketGrowthSteps)
        return estimate + Int(delta.rounded())
    }

    static func durationText(minutes: Int) -> String {
        let safe = max(minutes, 0)
        return "\(safe / 60):" + String(format: "%02d", safe % 60)
    }

    static func bandWidths(estimate: Int, shown: Int, rowWidth: CGFloat) -> (fill: CGFloat, hatch: CGFloat) {
        let full = max(rowWidth, 0)
        func width(_ minutes: Int) -> CGFloat {
            guard full > 0 else { return 0 }
            let span = CGFloat(max(minutes, 0)) / CGFloat(OpeningPanelTicketMetrics.fullWidthMinutes) * full
            return min(full, max(0, span))
        }
        let fill = width(estimate)
        let hatch = max(0, width(max(shown, estimate)) - fill)
        return (fill, hatch)
    }

    static func rowOpacity(index: Int, cut: Int) -> Double {
        index >= cut ? OpeningPanelTicketMetrics.belowRowOpacity : 1
    }

    /// 切れ目より上で、仕分けの結果を出したあとは番号を塗る。
    static func rankFilled(index: Int, cut: Int, settled: Bool) -> Bool {
        settled && index < cut
    }

    /// 似た乗車だけを数える。ほかの切符の到着が足りない行の中央値を埋めない。
    static func similarRide(
        ticket: Ticket,
        sessions: [WorkSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (count: Int, medianMinutes: Int) {
        let selection = RideSimilarity.select(
            title: ticket.title,
            tagIDs: BoardingForecast.tagFilter(for: ticket) ?? [],
            ticket: ticket,
            sessions: sessions,
            now: now,
            calendar: calendar
        )
        let matched = selection.chosen.filter(\.hasContentMatch).map(\.ride.activeSeconds)
        let median = BoardingForecast.predictedDuration(from: matched)?.minutes ?? 0
        return (matched.count, median)
    }

    /// 見積もりと、似た乗車が 3 回以上のときの中央値。足りなければ `--`。
    static func pair(estimate: Int, similarCount: Int, median: Int) -> OpeningPanelTicketPair {
        let shown = similarCount >= EstimateHeuristic.minimumSampleCount ? "\(max(median, 0))" : "--"
        return OpeningPanelTicketPair(estimate: "\(max(estimate, 0))", median: shown)
    }

    static func readout(today: Int, total: Int, freeMinutes: Int) -> String {
        let free = durationText(minutes: max(freeMinutes, 0))
        return "TODAY \(max(today, 0))/\(max(total, 0)) · 空き\(free)"
    }

    static func pileKeys(
        sequencing: Bool,
        powered: Bool,
        keys: [OpeningPanelSequencePicture.Key]
    ) -> [OpeningPanelPileKeyState] {
        guard sequencing, !keys.isEmpty else { return OpeningPanelPileKeyState.idle }
        return keys.map { key in
            OpeningPanelPileKeyState(
                id: key.id,
                title: key.title,
                count: key.count,
                lit: powered && key.enabled
            )
        }
    }

    static func touchRow(
        index: Int,
        ids: [UUID],
        cut: Int,
        sequencing: Bool,
        confirmed: Bool,
        powered: Bool,
        departed: Bool
    ) -> OpeningPanelTicketTouch {
        guard powered, !departed, ids.indices.contains(index) else { return .reject }
        if sequencing {
            return .reject
        }
        guard confirmed else { return .reject }
        let next = index + 1
        return next == cut ? .cutStays : .placeCut(next)
    }

    /// engine が立ったときだけ仕分けに入る。立たなければ `isSequencing` も立てない。
    @MainActor
    static func enterSequence(
        state: OpeningPanelState,
        model: OpeningPanelTicketsModel,
        sessions: [WorkSession],
        freeMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> Bool {
        guard model.beginSequence(
            sessions: sessions,
            freeMinutes: freeMinutes,
            now: now,
            calendar: calendar,
            in: context
        ) else { return false }
        state.pressSequence()
        return model.engine != nil && state.isSequencing
    }

    static func perform(
        _ touch: OpeningPanelTicketTouch,
        state: OpeningPanelState,
        model: OpeningPanelTicketsModel
    ) {
        switch touch {
        case .reject:
            state.rejectTouch()
        case .ignore:
            break
        case .cutStays:
            state.moveTodayCut(changed: false)
        case .placeCut(let next):
            model.placeCut(next)
            state.moveTodayCut(changed: true)
        }
    }
}

/// 切符の順と TODAY の区切り。MASTER を切ってもここが持つ。
@MainActor
@Observable
final class OpeningPanelTicketsModel {
    private(set) var rows: [OpeningPanelTicketRow] = []
    private(set) var cut: Int = OpeningPanelTicketMetrics.defaultCut
    /// 仕分けの結果を出したあと、切れ目より上の番号を塗る。
    private(set) var lineRanksFilled = false
    private(set) var engine: OpeningPanelSequenceEngine?
    private var openTickets: [UUID: Ticket] = [:]
    private var orderSnapshot: [UUID]?
    private var cutSnapshot = 0
    /// engine があるあいだに届いた切符。確定か破棄のあとで反映する。
    private var arrivedWhileSorting: (rows: [OpeningPanelTicketRow], tickets: [Ticket])?

    func sync(
        tickets: [Ticket],
        sessions: [WorkSession],
        now: Date = .now,
        calendar: Calendar = .current,
        refinedMinutes: (Ticket) -> Int? = { _ in nil }
    ) {
        adopt(
            OpeningPanelTickets.rows(
                from: tickets,
                sessions: sessions,
                now: now,
                calendar: calendar,
                refinedMinutes: refinedMinutes
            ),
            tickets: tickets
        )
    }

    /// 仕分け中は行と engine を残す。届いた切符は確定か破棄のあとで反映する。
    private func adopt(_ incoming: [OpeningPanelTicketRow], tickets: [Ticket]) {
        if engine != nil {
            arrivedWhileSorting = (incoming, tickets)
            return
        }
        apply(incoming, tickets: tickets)
    }

    private func apply(
        _ incoming: [OpeningPanelTicketRow],
        tickets: [Ticket],
        keepCut: Bool = false
    ) {
        openTickets = Dictionary(uniqueKeysWithValues: tickets.filter(\.isOpen).map { ($0.id, $0) })
        let incomingIDs = Set(incoming.map(\.id))
        if Set(rows.map(\.id)) == incomingIDs {
            let byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
            rows = rows.compactMap { byID[$0.id] }
        } else {
            rows = incoming
            if !keepCut {
                cut = OpeningPanelTickets.initialCut(count: rows.count)
            }
            orderSnapshot = nil
        }
        if cut > rows.count {
            cut = rows.count
        }
    }

    func show(
        tickets: [Ticket],
        arrivals: [UUID: OpeningPanelArrivalPlace],
        sessions: [WorkSession] = [],
        daysBelow: [UUID: Int] = [:],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        adopt(
            OpeningPanelTickets.rows(
                from: tickets,
                arrivals: arrivals,
                sessions: sessions,
                daysBelow: daysBelow,
                now: now,
                calendar: calendar
            ),
            tickets: tickets
        )
    }

    func applyArrival(id: UUID, place: OpeningPanelArrivalPlace) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let actual = place.minutes ?? rows[index].estimateMinutes
        guard rows[index].arrival != place || rows[index].actualMinutes != actual else { return }
        rows[index].arrival = place
        rows[index].actualMinutes = actual
    }

    func placeCut(_ next: Int) {
        cut = min(max(next, 0), rows.count)
    }

    var sequencePhase: OpeningPanelSequenceEngine.Phase? { engine?.phase }

    func beginSequence(
        sessions: [WorkSession],
        freeMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext,
        seed: UInt32? = nil
    ) -> Bool {
        let marks = (try? context.fetch(FetchDescriptor<OpeningSequenceBelowDays>())) ?? []
        let days = Dictionary(uniqueKeysWithValues: marks.map { ($0.ticketID, $0.consecutiveDays) })
        let stats = rows.compactMap { row -> OpeningPanelSequenceStat? in
            guard let ticket = openTickets[row.id] else { return nil }
            return OpeningPanelSequenceStat.make(
                ticket: ticket,
                sessions: sessions,
                now: now,
                calendar: calendar,
                daysBelow: days[row.id] ?? 0
            )
        }
        guard stats.count == rows.count else { return false }
        let resolved = seed ?? UInt32(truncatingIfNeeded: UInt64.random(in: .min ... .max))
        guard let started = OpeningPanelSequenceEngine.start(
            stats: stats,
            freeMinutes: Double(freeMinutes),
            seed: resolved
        ) else { return false }
        orderSnapshot = rows.map(\.id)
        cutSnapshot = cut
        lineRanksFilled = false
        engine = started
        return true
    }

    @discardableResult
    func chooseSequencePile(_ index: Int) -> Bool {
        guard var engine else { return false }
        let accepted = engine.choosePile(index)
        self.engine = engine
        publishIfSettled()
        return accepted
    }

    @discardableResult
    func chooseSequenceInsertedFirst(_ insertedFirst: Bool) -> Bool {
        guard var engine else { return false }
        let accepted = engine.chooseInsertedFirst(insertedFirst)
        self.engine = engine
        publishIfSettled()
        return accepted
    }

    @discardableResult
    func undoSequence() -> Bool {
        guard var engine else { return false }
        let accepted = engine.undo()
        self.engine = engine
        return accepted
    }

    func finishSequenceEarly() {
        guard var engine else { return }
        engine.finishEarly()
        self.engine = engine
        publishIfSettled()
    }

    func abandonSequence() {
        if engine != nil {
            lineRanksFilled = false
        }
        if let orderSnapshot {
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            let restored = orderSnapshot.compactMap { byID[$0] }
            if restored.count == rows.count {
                rows = restored
            }
            cut = min(cutSnapshot, rows.count)
        }
        engine = nil
        orderSnapshot = nil
        flushArrived()
    }

    /// 仕分けの結果を先頭から並べ、Hub の順として保存する。#208 の DEPART からも呼ぶ。
    func commitSequenceOrder(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        guard engine != nil else { return }
        commitEngine(in: context, now: now, calendar: calendar)
        flushArrived()
    }

    private func flushArrived() {
        guard let arrivedWhileSorting else { return }
        self.arrivedWhileSorting = nil
        let byID = Dictionary(uniqueKeysWithValues: arrivedWhileSorting.rows.map { ($0.id, $0) })
        let open = arrivedWhileSorting.tickets.filter(\.isOpen).sorted { $0.sortOrder < $1.sortOrder }
        let ordered = open.compactMap { byID[$0.id] }
        let incoming = ordered.count == open.count ? ordered : arrivedWhileSorting.rows
        apply(incoming, tickets: arrivedWhileSorting.tickets, keepCut: true)
    }

    private func publishIfSettled() {
        guard let engine, engine.phase != .sorting else { return }
        if engine.phase == .result {
            lineRanksFilled = true
        }
        let ids = engine.orderIDs
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let next = ids.compactMap { byID[$0] }
        guard next.count == rows.count else { return }
        rows = next
        cut = min(max(engine.lineIndex, 0), rows.count)
    }

    private func commitEngine(in context: ModelContext, now: Date, calendar: Calendar) {
        guard var engine else { return }
        if engine.phase != .result {
            engine.finishEarly()
        }
        self.engine = engine
        publishIfSettled()
        let ids = engine.orderIDs
        let orders = TicketSortOrdering.normalizedOrders(forOrderedIDs: ids)
        for (id, order) in orders {
            openTickets[id]?.sortOrder = order
        }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }
        if ordered.count == rows.count {
            rows = ordered
        }
        cut = min(max(engine.lineIndex, 0), rows.count)
        let record = OpeningSequenceRecord(
            dayStart: calendar.startOfDay(for: now),
            freeMinutes: engine.freeMinutes,
            lineIndex: engine.lineIndex,
            placementsJSON: OpeningPanelSequenceArchive.json(engine.placements),
            answersJSON: OpeningPanelSequenceArchive.json(engine.answers)
        )
        context.insert(record)
        writeBelowDays(engine.placements, now: now, calendar: calendar, in: context)
        self.engine = nil
        orderSnapshot = nil
        if context.hasChanges {
            try? context.save()
        }
    }

    private func writeBelowDays(
        _ placements: [OpeningPanelSequencePlacement],
        now: Date,
        calendar: Calendar,
        in context: ModelContext
    ) {
        let existing = (try? context.fetch(FetchDescriptor<OpeningSequenceBelowDays>())) ?? []
        let previous = existing.map {
            OpeningPanelSequenceDayMark(
                ticketID: $0.ticketID,
                consecutiveDays: $0.consecutiveDays,
                lastBelowDay: $0.lastBelowDay
            )
        }
        let updated = OpeningPanelSequenceDays.advance(
            previous: previous,
            placements: placements,
            day: now,
            calendar: calendar
        )
        var stored: [UUID: OpeningSequenceBelowDays] = [:]
        for row in existing where stored[row.ticketID] == nil {
            stored[row.ticketID] = row
        }
        for mark in updated {
            let row = stored[mark.ticketID] ?? OpeningSequenceBelowDays(
                ticketID: mark.ticketID,
                consecutiveDays: 0,
                lastBelowDay: nil
            )
            if stored[mark.ticketID] == nil {
                context.insert(row)
                stored[mark.ticketID] = row
            }
            row.consecutiveDays = mark.consecutiveDays
            row.lastBelowDay = mark.lastBelowDay
        }
    }
}

struct TicketsModule: View {
    var state: OpeningPanelState
    var model: OpeningPanelTicketsModel
    var calendar: Calendar = .current

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("TicketsModule")
        if state.isSequencing, let engine = model.engine {
            OpeningPanelSequenceBoard(
                picture: OpeningPanelSequencePicture.make(
                    engine: engine,
                    title: { id in
                        model.rows.first { $0.id == id }?.title ?? ""
                    },
                    calendar: calendar
                ),
                onInsertedFirst: { insertedFirst in
                    if model.chooseSequenceInsertedFirst(insertedFirst) {
                        state.noteSequenceRow(accepted: true)
                    } else {
                        state.rejectTouch()
                    }
                },
                onUndo: {
                    if model.undoSequence() {
                        state.noteSequenceRow(accepted: true)
                    } else {
                        state.rejectTouch()
                    }
                }
            )
        } else {
            ticketList
        }
    }

    private var ticketList: some View {
        VStack(spacing: 0) {
            ForEach(Array(rowSlots.enumerated()), id: \.offset) { index, slot in
                Button {
                    touchRow(index)
                } label: {
                    OpeningPanelTicketRowView(
                        slot: slot,
                        index: index,
                        cut: model.cut,
                        ranksFilled: model.lineRanksFilled
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .openingPanelAction(.ticketRow(index), perform: { touchRow(index) })
            }
            if let more = moreLabel {
                Text(more)
                    .font(.system(size: 9))
                    .tracking(0.54)
                    .foregroundStyle(OpeningPanelTokens.Palette.amber)
                    .opacity(OpeningPanelTicketMetrics.belowRowOpacity)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, OpeningPanelTicketMetrics.rankWidth + OpeningPanelTicketMetrics.rowGap)
                    .frame(height: OpeningPanelTicketMetrics.rowHeight)
                    .accessibilityLabel(more)
            }
        }
        .padding(.top, OpeningPanelTicketMetrics.contentTop)
        .padding(.horizontal, OpeningPanelTicketMetrics.contentHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var visibleSpan: (shown: Int, hidden: Int) {
        OpeningPanelSequenceMath.visibleSpan(line: model.cut, total: model.rows.count)
    }

    private var moreLabel: String? {
        guard state.ticketsStage != .dark, visibleSpan.hidden > 0 else { return nil }
        return "ほか \(visibleSpan.hidden) 枚"
    }

    private var ticketsConfirmed: Bool {
        state.confirmation(of: .tickets) == .confirmed
    }

    private func touchRow(_ index: Int) {
        OpeningPanelTickets.perform(
            OpeningPanelTickets.touchRow(
                index: index,
                ids: model.rows.map(\.id),
                cut: model.cut,
                sequencing: state.isSequencing,
                confirmed: ticketsConfirmed,
                powered: state.isPowered,
                departed: state.hasDeparted
            ),
            state: state,
            model: model
        )
    }

    private var rowSlots: [OpeningPanelTicketSlot] {
        let count = visibleSpan.shown
        switch state.ticketsStage {
        case .dark:
            return []
        case .backlight:
            return Array(repeating: .empty, count: count)
        case .cursor(let rows):
            return (0..<count).map { index in
                index < rows ? .cursor : .empty
            }
        case .shown(let shown):
            return model.rows.prefix(count).enumerated().map { index, row in
                index < shown ? .ticket(row) : .empty
            }
        }
    }
}

private enum OpeningPanelTicketSlot: Equatable {
    case empty
    case cursor
    case ticket(OpeningPanelTicketRow)
}

private struct OpeningPanelTicketRowView: View {
    var slot: OpeningPanelTicketSlot
    var index: Int
    var cut: Int
    var ranksFilled: Bool

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Rectangle()
                .fill(index == cut - 1 ? OpeningPanelTokens.Palette.amber : OpeningPanelTicketMetrics.rowLine)
                .frame(height: 1)
        }
        .frame(height: OpeningPanelTicketMetrics.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(hint)
    }

    @ViewBuilder
    private var content: some View {
        switch slot {
        case .empty:
            Color.clear
        case .cursor:
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(OpeningPanelTokens.Palette.amber.opacity(0.6))
                .frame(height: 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .ticket(let row):
            let below = index >= cut
            let fade = OpeningPanelTickets.rowOpacity(index: index, cut: cut)
            let pair = OpeningPanelTickets.pair(
                estimate: row.estimateMinutes,
                similarCount: row.similarCount,
                median: row.similarMedianMinutes
            )
            HStack(spacing: OpeningPanelTicketMetrics.rowGap) {
                rank
                    .opacity(fade)
                Text(row.title)
                    .font(.system(size: OpeningPanelTicketMetrics.titleSize))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(fade)
                if below, row.daysBelow > 0 {
                    Text("\(row.daysBelow)日")
                        .font(.system(size: OpeningPanelTicketMetrics.pairSize))
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .strokeBorder(OpeningPanelTokens.Palette.amber.opacity(0.35), lineWidth: 1)
                        }
                        .opacity(OpeningPanelTicketMetrics.badgeOpacity)
                }
                HStack(spacing: 0) {
                    Text(pair.estimate)
                    Text("/")
                        .opacity(OpeningPanelTicketMetrics.slashOpacity)
                    Text(pair.median)
                }
                .font(.system(size: OpeningPanelTicketMetrics.pairSize))
                .monospacedDigit()
                .lineLimit(1)
                .opacity(below ? fade : OpeningPanelTicketMetrics.pairOpacity)
            }
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
        }
    }

    private var rank: some View {
        let filled = OpeningPanelTickets.rankFilled(index: index, cut: cut, settled: ranksFilled)
        return Text("\(index + 1)")
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(filled ? OpeningPanelTicketMetrics.rankInk : OpeningPanelTokens.Palette.amber)
            .frame(width: OpeningPanelTicketMetrics.rankWidth, height: OpeningPanelTicketMetrics.rankHeight)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(OpeningPanelTokens.Palette.amber)
                }
            }
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .strokeBorder(OpeningPanelTokens.Palette.amber, lineWidth: 1)
                }
            }
    }

    private var accessibilityLabel: String {
        switch slot {
        case .empty, .cursor:
            return "起動中"
        case .ticket(let row):
            return "\(index + 1) \(row.title)"
        }
    }

    private var accessibilityValue: String {
        guard case .ticket(let row) = slot else { return "" }
        let pair = OpeningPanelTickets.pair(
            estimate: row.estimateMinutes,
            similarCount: row.similarCount,
            median: row.similarMedianMinutes
        )
        var parts = ["\(pair.estimate)/\(pair.median)"]
        if index >= cut, row.daysBelow > 0 {
            parts.append("\(row.daysBelow)日")
        }
        return parts.joined(separator: " ")
    }

    private var hint: String {
        switch slot {
        case .empty, .cursor:
            return ""
        case .ticket:
            return "この行の下へ区切りを移します"
        }
    }
}

struct TicketsSequenceKey: View {
    var state: OpeningPanelState
    var phase: OpeningPanelSequenceEngine.Phase?
    var onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .openingPanelAction(.sequence, perform: onPress)
        .contentShape(Rectangle())
        .accessibilityLabel("SEQ")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(hint)
    }

    private var accessibilityValue: String {
        guard state.isSequencing else { return "待機" }
        switch phase {
        case .sorting, nil: return "仕分け"
        case .comparing: return "決め直し"
        case .result: return "結果"
        }
    }

    private var hint: String {
        if !state.isPowered {
            return "電気が来ると使えます"
        }
        if state.confirmation(of: .tickets) != .confirmed {
            return "切符の確認が済むと順を入れ替えられます"
        }
        if state.isSequencing {
            if phase == .result {
                return "この順番を採用します"
            }
            return "ここまでの仕分けで結果を出します"
        }
        return "切符を仕分けます"
    }
}

struct TicketsConfirmKey: View {
    var state: OpeningPanelState
    var onPress: () -> Void

    private var standbyAvailable: Bool {
        state.isPowered && state.confirmation(of: .tickets) == .unconfirmed
    }

    private var okLit: Bool {
        guard state.isPowered else { return false }
        switch state.confirmation(of: .tickets) {
        case .confirming, .confirmed:
            return true
        case .unconfirmed:
            return false
        }
    }

    var body: some View {
        Button(action: onPress) {
            OpeningPanelConfirmKey(
                topAvailable: standbyAvailable,
                bottomLit: okLit,
                sunk: okLit,
                showsNextEdge: state.nextAutomaticModule == .tickets
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .openingPanelAction(.ticketsKey, perform: onPress)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("TKT")
        .accessibilityValue(okLit ? "OK" : (standbyAvailable ? "STBY" : "消灯"))
        .accessibilityHint(hint)
    }

    private var hint: String {
        if !state.isPowered {
            return "電気が来ると確認できます"
        }
        if state.confirmation(of: .tickets) == .unconfirmed {
            return "切符の確認を始めます"
        }
        return "切符の確認をやり直します"
    }
}
