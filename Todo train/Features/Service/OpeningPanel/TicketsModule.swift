//
//  TicketsModule.swift
//  Todo train
//
//  切符の窓。段名とレールと SEQ のキャップは格子が描く。
//  行の寸法は参照モックの最終 CSS。並びと TODAY の区切りは盤を落としても残す。
//

import SwiftData
import SwiftUI

enum OpeningPanelTicketMetrics {
    static let rowHeight: CGFloat = 21
    static let rowGap: CGFloat = 6
    static let titleSize: CGFloat = 12
    static let durationSize: CGFloat = 11
    static let durationWidth: CGFloat = 32
    static let durationOpacity: Double = 0.8
    static let contentTop: CGFloat = 2
    static let contentHorizontal: CGFloat = 6
    static let bandInset: CGFloat = 2
    static let digitScale: CGFloat = 0.17
    static let digitSize = CGSize(width: 9, height: 17)
    static let cursorGlyphs = 16
    static let belowNumberOpacity: Double = 0.3
    static let fullWidthMinutes = 120
    static let defaultCut = 3
    static let estimateFill = Color(red: 1, green: 176 / 255, blue: 0, opacity: 0.13)
    static let hatchInk = Color(red: 1, green: 176 / 255, blue: 0, opacity: 0.32)
    static let rowLine = Color(red: 34 / 255, green: 34 / 255, blue: 34 / 255)
    static let segmentOff = Color(red: 1, green: 176 / 255, blue: 0, opacity: 0.07)
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
}

enum OpeningPanelTicketTouch: Equatable {
    case reject
    case ignore
    case select(UUID)
    case duplicate
    case placeCut(Int)
    case cutStays
}

enum OpeningPanelTickets {
    static func slotName(index: Int) -> String {
        switch index {
        case 0: "先発"
        case 1: "次発"
        case 2: "次々発"
        default: "\(index + 1)"
        }
    }

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
                return OpeningPanelTicketRow(
                    id: ticket.id,
                    title: ticket.title,
                    estimateMinutes: resolved.estimate,
                    actualMinutes: resolved.actual
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

    static func numberOpacity(index: Int, cut: Int) -> Double {
        index >= cut ? OpeningPanelTicketMetrics.belowNumberOpacity : 1
    }

    static func numberDigit(
        index: Int,
        id: UUID,
        picks: [UUID],
        sequencing: Bool
    ) -> Character? {
        let number: Int
        if sequencing {
            guard let pick = picks.firstIndex(of: id) else { return nil }
            number = pick + 1
        } else {
            number = index + 1
        }
        let text = String(number)
        guard text.count == 1 else { return nil }
        return text.first
    }

    /// 選んだ順を先頭へ。選ばなかった切符は元の順で後ろに続く。
    static func reorderedIDs(_ ids: [UUID], picks: [UUID]) -> [UUID] {
        var order = ids
        for (target, id) in picks.enumerated() {
            guard let from = order.firstIndex(of: id), from != target else { continue }
            let destination = ServiceCabinSequence.consistMoveOffset(from: from, to: target)
            let item = order.remove(at: from)
            let adjusted = destination - (from < destination ? 1 : 0)
            let index = min(max(adjusted, 0), order.count)
            order.insert(item, at: index)
        }
        return order
    }

    static func cut(atRailY y: CGFloat, count: Int) -> Int {
        let steps = ((y - OpeningPanelTicketMetrics.contentTop) / OpeningPanelTicketMetrics.rowHeight).rounded()
        let raw = Int(steps)
        return min(max(raw, 0), max(count, 0))
    }

    static func touchRow(
        index: Int,
        ids: [UUID],
        cut: Int,
        picks: [UUID],
        sequencing: Bool,
        confirmed: Bool,
        powered: Bool,
        departed: Bool
    ) -> OpeningPanelTicketTouch {
        guard powered, !departed, ids.indices.contains(index) else { return .reject }
        let id = ids[index]
        if sequencing {
            return picks.contains(id) ? .duplicate : .select(id)
        }
        guard confirmed else { return .reject }
        let next = index + 1
        return next == cut ? .cutStays : .placeCut(next)
    }

    static func touchRail(
        y: CGFloat,
        began: Bool,
        count: Int,
        cut: Int,
        sequencing: Bool,
        confirmed: Bool,
        powered: Bool,
        departed: Bool
    ) -> OpeningPanelTicketTouch {
        guard powered, confirmed, !sequencing, !departed else {
            return began ? .reject : .ignore
        }
        let next = self.cut(atRailY: y, count: count)
        if next == cut {
            return began ? .cutStays : .ignore
        }
        return .placeCut(next)
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
        case .select(let id):
            model.select(id)
            state.noteSequenceRow(accepted: true)
        case .duplicate:
            state.noteSequenceRow(accepted: false)
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
    private(set) var picks: [UUID] = []
    private var openTickets: [UUID: Ticket] = [:]

    func sync(
        tickets: [Ticket],
        sessions: [WorkSession],
        now: Date = .now,
        calendar: Calendar = .current,
        refinedMinutes: (Ticket) -> Int? = { _ in nil }
    ) {
        let incoming = OpeningPanelTickets.rows(
            from: tickets,
            sessions: sessions,
            now: now,
            calendar: calendar,
            refinedMinutes: refinedMinutes
        )
        openTickets = Dictionary(uniqueKeysWithValues: tickets.filter(\.isOpen).map { ($0.id, $0) })
        let incomingIDs = Set(incoming.map(\.id))
        if Set(rows.map(\.id)) == incomingIDs {
            let byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
            rows = rows.compactMap { byID[$0.id] }
            picks = picks.filter { incomingIDs.contains($0) }
        } else {
            rows = incoming
            picks = []
            cut = OpeningPanelTickets.initialCut(count: rows.count)
        }
        if cut > rows.count {
            cut = rows.count
        }
    }

    func select(_ id: UUID) {
        guard rows.contains(where: { $0.id == id }), !picks.contains(id) else { return }
        picks.append(id)
    }

    func placeCut(_ next: Int) {
        cut = min(max(next, 0), rows.count)
    }

    func dropPicks() {
        picks.removeAll()
    }

    /// 選んだ順で先頭から並べ、Hub の順として保存する。#208 の DEPART からも呼ぶ。
    func commitSequenceOrder(in context: ModelContext) {
        let ids = OpeningPanelTickets.reorderedIDs(rows.map(\.id), picks: picks)
        let orders = TicketSortOrdering.normalizedOrders(forOrderedIDs: ids)
        for (id, order) in orders {
            openTickets[id]?.sortOrder = order
        }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        rows = ids.compactMap { byID[$0] }
        picks = []
        if context.hasChanges {
            try? context.save()
        }
    }
}

struct TicketsModule: View {
    var state: OpeningPanelState
    var model: OpeningPanelTicketsModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rowSlots.enumerated()), id: \.offset) { index, slot in
                Button {
                    OpeningPanelTickets.perform(
                        OpeningPanelTickets.touchRow(
                            index: index,
                            ids: model.rows.map(\.id),
                            cut: model.cut,
                            picks: model.picks,
                            sequencing: state.isSequencing,
                            confirmed: ticketsConfirmed,
                            powered: state.isPowered,
                            departed: state.hasDeparted
                        ),
                        state: state,
                        model: model
                    )
                } label: {
                    OpeningPanelTicketRowView(
                        slot: slot,
                        index: index,
                        cut: model.cut,
                        picks: model.picks,
                        sequencing: state.isSequencing,
                        growthStep: state.ticketGrowthStep
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, OpeningPanelTicketMetrics.contentTop)
        .padding(.horizontal, OpeningPanelTicketMetrics.contentHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var ticketsConfirmed: Bool {
        state.confirmation(of: .tickets) == .confirmed
    }

    private var rowSlots: [OpeningPanelTicketSlot] {
        switch state.ticketsStage {
        case .dark:
            return []
        case .backlight:
            return Array(repeating: .empty, count: model.rows.count)
        case .cursor(let rows):
            let count = max(model.rows.count, rows)
            return (0..<count).map { index in
                index < rows ? .cursor : .empty
            }
        case .shown(let shown):
            return model.rows.enumerated().map { index, row in
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
    var picks: [UUID]
    var sequencing: Bool
    var growthStep: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                band
                content
            }
            .frame(maxWidth: .infinity)
            .frame(height: OpeningPanelTicketMetrics.rowHeight - 1)
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
    private var band: some View {
        if case .ticket(let row) = slot {
            GeometryReader { geo in
                let minutes = OpeningPanelTickets.shownMinutes(
                    estimate: row.estimateMinutes,
                    actual: row.actualMinutes,
                    step: growthStep
                )
                let widths = OpeningPanelTickets.bandWidths(
                    estimate: row.estimateMinutes,
                    shown: minutes,
                    rowWidth: geo.size.width
                )
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(OpeningPanelTicketMetrics.estimateFill)
                        .frame(width: widths.fill)
                    OpeningPanelTicketHatch()
                        .frame(width: widths.hatch)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, OpeningPanelTicketMetrics.bandInset)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch slot {
        case .empty:
            Color.clear
        case .cursor:
            Text(String(repeating: "█", count: OpeningPanelTicketMetrics.cursorGlyphs))
                .font(.system(size: OpeningPanelTicketMetrics.titleSize))
                .foregroundStyle(OpeningPanelTokens.Palette.amber)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .ticket(let row):
            let minutes = OpeningPanelTickets.shownMinutes(
                estimate: row.estimateMinutes,
                actual: row.actualMinutes,
                step: growthStep
            )
            HStack(spacing: OpeningPanelTicketMetrics.rowGap) {
                OpeningPanelTicketDigit(
                    character: OpeningPanelTickets.numberDigit(
                        index: index,
                        id: row.id,
                        picks: picks,
                        sequencing: sequencing
                    ),
                    fallback: numberFallback(for: row),
                    opacity: OpeningPanelTickets.numberOpacity(index: index, cut: cut)
                )
                Text(row.title)
                    .font(.system(size: OpeningPanelTicketMetrics.titleSize))
                    .foregroundStyle(OpeningPanelTokens.Palette.amber)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(OpeningPanelTickets.durationText(minutes: minutes))
                    .font(.system(size: OpeningPanelTicketMetrics.durationSize))
                    .monospacedDigit()
                    .foregroundStyle(OpeningPanelTokens.Palette.amber)
                    .opacity(OpeningPanelTicketMetrics.durationOpacity)
                    .frame(width: OpeningPanelTicketMetrics.durationWidth, alignment: .trailing)
                    .lineLimit(1)
            }
        }
    }

    private func numberFallback(for row: OpeningPanelTicketRow) -> String? {
        guard sequencing else {
            let number = index + 1
            return number > 9 ? String(number) : nil
        }
        guard let pick = picks.firstIndex(of: row.id) else { return nil }
        let number = pick + 1
        return number > 9 ? String(number) : nil
    }

    private var accessibilityLabel: String {
        switch slot {
        case .empty, .cursor:
            return "起動中"
        case .ticket(let row):
            return "\(OpeningPanelTickets.slotName(index: index)) \(row.title)"
        }
    }

    private var accessibilityValue: String {
        guard case .ticket(let row) = slot else { return "" }
        if sequencing {
            if let pick = picks.firstIndex(of: row.id) {
                return "\(pick + 1)"
            }
            return "未選択"
        }
        let minutes = OpeningPanelTickets.shownMinutes(
            estimate: row.estimateMinutes,
            actual: row.actualMinutes,
            step: growthStep
        )
        return OpeningPanelTickets.durationText(minutes: minutes)
    }

    private var hint: String {
        switch slot {
        case .empty, .cursor:
            return ""
        case .ticket:
            if sequencing {
                return "この切符に番号を付けます"
            }
            return "この行の下へ区切りを移します"
        }
    }
}

private struct OpeningPanelTicketDigit: View {
    var character: Character?
    var fallback: String?
    var opacity: Double

    var body: some View {
        Group {
            if let fallback {
                Text(fallback)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(OpeningPanelTokens.Palette.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Canvas { context, _ in
                    context.scaleBy(
                        x: OpeningPanelTicketMetrics.digitScale,
                        y: OpeningPanelTicketMetrics.digitScale
                    )
                    let lit = character.map { OpeningPanelClockGlyph.segments(for: $0) } ?? []
                    for segment in OpeningPanelClockSegment.allCases {
                        let rect = OpeningPanelClockLayout.localSegment(segment)
                        let color = lit.contains(segment)
                            ? OpeningPanelTokens.Palette.amber
                            : OpeningPanelTicketMetrics.segmentOff
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(
            width: OpeningPanelTicketMetrics.digitSize.width,
            height: OpeningPanelTicketMetrics.digitSize.height
        )
        .opacity(opacity)
        .accessibilityHidden(true)
    }
}

private struct OpeningPanelTicketHatch: View {
    var body: some View {
        Canvas { context, size in
            var x = -size.height
            let limit = size.width + size.height
            while x < limit {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                context.stroke(path, with: .color(OpeningPanelTicketMetrics.hatchInk), lineWidth: 2)
                x += 5
            }
        }
        .allowsHitTesting(false)
    }
}

struct TicketsSequenceKey: View {
    var state: OpeningPanelState
    var onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SEQ")
        .accessibilityValue(state.isSequencing ? "並べ替え" : "待機")
        .accessibilityHint(hint)
    }

    private var hint: String {
        if !state.isPowered {
            return "電気が来ると使えます"
        }
        if state.confirmation(of: .tickets) != .confirmed {
            return "切符の確認が済むと順を入れ替えられます"
        }
        if state.isSequencing {
            return "選んだ順で先頭から並べます"
        }
        return "切符の順を入れ替えます"
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
