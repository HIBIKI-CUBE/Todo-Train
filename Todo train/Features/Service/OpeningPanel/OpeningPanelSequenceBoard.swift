//
//  OpeningPanelSequenceBoard.swift
//  Todo train
//
//  SEQ の仕分け。先頭の 1 枚と、後ろに待つ 3 枚。右の山は今日／できれば／あとで。
//

import SwiftUI

struct OpeningPanelSequencePicture: Equatable {
    struct Card: Equatable, Identifiable {
        var id: UUID
        var title: String
        var due: String
        var pair: String
    }

    struct Key: Equatable, Identifiable {
        var id: Int
        var title: String
        var count: String
        var enabled: Bool
    }

    struct Row: Equatable, Identifiable {
        var id: UUID
        var rank: Int
        var title: String
        var pair: String
        var below: Bool
        var days: Int
        var lineBelow: Bool
    }

    enum Body: Equatable {
        case sorting(front: Card?, waiting: [Card], ended: Bool)
        case comparing(upper: Card, lower: Card, upcoming: String)
        case result(rows: [Row], hidden: Int, lineAtTop: Bool)
    }

    var status: String
    var progress: Double
    var canUndo: Bool
    var keys: [Key]
    var body: Body

    static func make(
        engine: OpeningPanelSequenceEngine,
        title: (UUID) -> String,
        calendar: Calendar
    ) -> OpeningPanelSequencePicture {
        let keys = keyRow(engine)
        switch engine.phase {
        case .sorting:
            let front = engine.frontIndex.flatMap { card(engine.stat(at: $0), title: title, calendar: calendar) }
            let waiting = engine.waitingIndices.compactMap { card(engine.stat(at: $0), title: title, calendar: calendar) }
            return OpeningPanelSequencePicture(
                status: "仕分け \(engine.sortedCount)/\(engine.sortingTotal)",
                progress: engine.progress,
                canUndo: engine.canUndo,
                keys: keys,
                body: .sorting(front: front, waiting: waiting, ended: engine.showsEndOfQueue)
            )
        case .comparing:
            let pair = engine.comparison
            let upper = pair.flatMap { card(engine.stat(at: $0.inserted), title: title, calendar: calendar) }
            let lower = pair.flatMap { card(engine.stat(at: $0.other), title: title, calendar: calendar) }
            let names = pair?.upcoming.compactMap { engine.stat(at: $0)?.id }.map(title) ?? []
            let upcoming = names.isEmpty ? "" : "つぎ \(names.joined(separator: " · "))"
            return OpeningPanelSequencePicture(
                status: "決め直し 比べ \(engine.comparisons + 1)回目",
                progress: engine.progress,
                canUndo: engine.canUndo,
                keys: keys,
                body: .comparing(
                    upper: upper ?? Card(id: UUID(), title: "", due: "", pair: ""),
                    lower: lower ?? Card(id: UUID(), title: "", due: "", pair: ""),
                    upcoming: upcoming
                )
            )
        case .result:
            let order = engine.orderIDs
            let line = engine.lineIndex
            let span = OpeningPanelSequenceMath.visibleSpan(line: line, total: order.count)
            let rows = order.prefix(span.shown).enumerated().map { offset, id in
                let stat = engine.stat(id)
                return Row(
                    id: id,
                    rank: offset + 1,
                    title: title(id),
                    pair: pairText(stat),
                    below: offset >= line,
                    days: offset >= line ? (stat?.daysBelowLine ?? 0) : 0,
                    lineBelow: offset == line - 1
                )
            }
            let free = OpeningPanelTickets.durationText(minutes: Int(engine.freeMinutes.rounded()))
            return OpeningPanelSequencePicture(
                status: "TODAY \(line)/\(order.count) · 空き\(free)",
                progress: engine.progress,
                canUndo: false,
                keys: [],
                body: .result(rows: rows, hidden: span.hidden, lineAtTop: line == 0 && !order.isEmpty)
            )
        }
    }

    private static func keyRow(_ engine: OpeningPanelSequenceEngine) -> [Key] {
        let titles: [String]
        let counts: [String]
        switch engine.phase {
        case .sorting:
            titles = ["今日", "できれば", "あとで"]
            counts = engine.pileCounts.map(String.init)
        case .comparing:
            titles = ["上が先", "下が先", ""]
            counts = ["", "", ""]
        case .result:
            return []
        }
        return zip(titles.indices, titles).map { index, title in
            Key(
                id: index,
                title: title,
                count: counts[index],
                enabled: engine.keyEnabled[index]
            )
        }
    }

    private static func card(
        _ stat: OpeningPanelSequenceStat?,
        title: (UUID) -> String,
        calendar: Calendar
    ) -> Card? {
        guard let stat else { return nil }
        return Card(id: stat.id, title: title(stat.id), due: dueText(stat.dueDate, calendar: calendar), pair: pairText(stat))
    }

    private static func pairText(_ stat: OpeningPanelSequenceStat?) -> String {
        guard let stat else { return "" }
        let median = stat.similarCount >= EstimateHeuristic.minimumSampleCount
            ? "\(stat.similarMedianMinutes)"
            : "--"
        return "\(stat.estimateMinutes)/\(median)"
    }

    private static func dueText(_ date: Date?, calendar: Calendar) -> String {
        guard let date else { return "締切なし" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return "締切 \(formatter.string(from: date))"
    }
}

struct OpeningPanelSequenceBoard: View {
    var picture: OpeningPanelSequencePicture
    var onPile: (Int) -> Void
    var onInsertedFirst: (Bool) -> Void
    var onUndo: () -> Void

    private var frames: OpeningPanelSequenceLayout.Frames {
        OpeningPanelSequenceLayout.frames(in: OpeningPanelHitLayout.ticketWindow)
    }

    var body: some View {
        let frames = frames
        ZStack(alignment: .topLeading) {
            switch picture.body {
            case .sorting(let front, let waiting, let ended):
                sorting(front: front, waiting: waiting, ended: ended, frames: frames)
            case .comparing(let upper, let lower, let upcoming):
                comparing(upper: upper, lower: lower, upcoming: upcoming, frames: frames)
            case .result(let rows, let hidden, let lineAtTop):
                VStack(alignment: .leading, spacing: 2) {
                    Text(picture.status)
                        .font(.system(size: 9))
                        .foregroundStyle(OpeningPanelTokens.Palette.amber)
                        .lineLimit(1)
                    result(rows: rows, hidden: hidden, lineAtTop: lineAtTop)
                }
            }
            if !picture.keys.isEmpty {
                bar(frames: frames)
                ForEach(picture.keys) { key in
                    pileKey(key, frame: frames.keys[key.id])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func bar(frames: OpeningPanelSequenceLayout.Frames) -> some View {
        HStack(spacing: 4) {
            Text(picture.status)
                .font(.system(size: 9))
                .foregroundStyle(OpeningPanelTokens.Palette.amber)
                .lineLimit(1)
            progress
            Button(action: onUndo) {
                Text("取消")
                    .font(.system(size: 9))
                    .foregroundStyle(OpeningPanelTokens.Palette.amber)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: 1)
                            .strokeBorder(OpeningPanelTokens.Palette.amber.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .frame(width: frames.undo.width, height: frames.undo.height)
            .opacity(picture.canUndo ? 1 : 0.3)
            .openingPanelAction(.sequenceUndo, perform: onUndo)
            .accessibilityLabel("取消")
            .accessibilityHint("直前の仕分けを取り消します")
        }
        .frame(width: frames.bar.width, height: frames.bar.height, alignment: .leading)
        .offset(x: frames.bar.minX, y: frames.bar.minY)
    }

    private var progress: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.amber.opacity(0.12))
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.amber)
                    .frame(width: max(0, geo.size.width * picture.progress))
            }
        }
        .frame(height: 6)
        .accessibilityLabel(picture.status)
    }

    private func pileKey(_ key: OpeningPanelSequencePicture.Key, frame: CGRect) -> some View {
        let action = {
            if picture.bodyIsComparing {
                guard key.id < 2 else {
                    onPile(key.id)
                    return
                }
                onInsertedFirst(key.id == 0)
            } else {
                onPile(key.id)
            }
        }
        return Button(action: action) {
            VStack(spacing: 1) {
                Text(key.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !key.count.isEmpty {
                    Text(key.count)
                        .font(.system(size: 9))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(key.enabled ? OpeningPanelTokens.Palette.amber : OpeningPanelTokens.Palette.amber.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OpeningPanelTokens.Palette.key(0x2F3133))
            .overlay {
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(OpeningPanelTokens.Palette.amber.opacity(key.enabled ? 0.45 : 0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(key.enabled ? 1 : 0.45)
        .openingPanelAction(.sequencePile(key.id), perform: action)
        .accessibilityLabel(key.title.isEmpty ? "消灯" : key.title)
        .accessibilityValue(key.count)
        .accessibilityHint(keyHint(key))
    }

    private func keyHint(_ key: OpeningPanelSequencePicture.Key) -> String {
        guard key.enabled else { return "このキーは使えません" }
        if picture.bodyIsComparing {
            return key.id == 0 ? "上の切符を先にします" : "下の切符を先にします"
        }
        return "この山に入れます"
    }

    private func sorting(
        front: OpeningPanelSequencePicture.Card?,
        waiting: [OpeningPanelSequencePicture.Card],
        ended: Bool,
        frames: OpeningPanelSequenceLayout.Frames
    ) -> some View {
        let body = frames.column.insetBy(dx: 0, dy: 0)
        let top = body.minY + frames.bar.height
        return VStack(alignment: .leading, spacing: 1) {
            if let front {
                frontCard(front)
                    .frame(height: 34)
            }
            ForEach(Array(waiting.enumerated()), id: \.element.id) { index, card in
                waitingRow(card, depth: index)
            }
            if ended {
                Text("ここまで")
                    .font(.system(size: 9))
                    .foregroundStyle(OpeningPanelTokens.Palette.amber.opacity(0.35))
            }
        }
        .frame(width: frames.column.width, alignment: .topLeading)
        .offset(x: frames.column.minX, y: top)
    }

    private func comparing(
        upper: OpeningPanelSequencePicture.Card,
        lower: OpeningPanelSequencePicture.Card,
        upcoming: String,
        frames: OpeningPanelSequenceLayout.Frames
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            choiceCard(upper, first: true)
                .frame(width: frames.upperCard.width, height: max(20, frames.upperCard.height - 8))
            choiceCard(lower, first: false)
                .frame(width: frames.lowerCard.width, height: max(20, frames.lowerCard.height - 8))
            if !upcoming.isEmpty {
                Text(upcoming)
                    .font(.system(size: 9))
                    .foregroundStyle(OpeningPanelTokens.Palette.amber.opacity(0.62))
                    .lineLimit(1)
            }
        }
        .frame(width: frames.column.width, alignment: .topLeading)
        .offset(x: frames.column.minX, y: frames.bar.maxY)
    }

    private func result(
        rows: [OpeningPanelSequencePicture.Row],
        hidden: Int,
        lineAtTop: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if lineAtTop {
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.amber)
                    .frame(height: 1)
            }
            ForEach(rows) { row in
                resultRow(row)
            }
            if hidden > 0 {
                Text("ほか \(hidden) 枚")
                    .font(.system(size: 9))
                    .foregroundStyle(OpeningPanelTokens.Palette.amber.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 4)
    }

    private func frontCard(_ card: OpeningPanelSequencePicture.Card) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(card.title)
                .font(.system(size: 13))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(card.due)
                Text(card.pair)
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .font(.system(size: 9))
        }
        .foregroundStyle(OpeningPanelTokens.Palette.amber)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .overlay {
            RoundedRectangle(cornerRadius: 1)
                .strokeBorder(OpeningPanelTokens.Palette.amber.opacity(0.45), lineWidth: 1)
        }
    }

    private func waitingRow(_ card: OpeningPanelSequencePicture.Card, depth: Int) -> some View {
        let opacity = [0.62, 0.42, 0.27][min(depth, 2)]
        return HStack(spacing: 4) {
            Text(card.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(card.pair)
                .monospacedDigit()
        }
        .font(.system(size: 10))
        .foregroundStyle(OpeningPanelTokens.Palette.amber)
        .opacity(opacity)
        .frame(height: 14)
        .padding(.horizontal, 4)
    }

    private func choiceCard(_ card: OpeningPanelSequencePicture.Card, first: Bool) -> some View {
        Button {
            onInsertedFirst(first)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(card.due)
                    Text(card.pair).monospacedDigit().opacity(0.7)
                }
                .font(.system(size: 9))
            }
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(
                        OpeningPanelTokens.Palette.amber.opacity(first ? 0.45 : 0.25),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .openingPanelAction(first ? .sequenceCard(0) : .sequenceCard(1)) {
            onInsertedFirst(first)
        }
        .accessibilityLabel(card.title)
        .accessibilityValue(card.pair)
        .accessibilityHint(first ? "上の切符を先にします" : "下の切符を先にします")
    }

    private func resultRow(_ row: OpeningPanelSequencePicture.Row) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("\(row.rank)")
                    .font(.system(size: 9))
                    .frame(width: 14)
                Text(row.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.days > 0 {
                    Text("\(row.days)日")
                        .font(.system(size: 9))
                        .padding(.horizontal, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 1)
                                .strokeBorder(OpeningPanelTokens.Palette.amber.opacity(0.35), lineWidth: 1)
                        }
                }
                Text(row.pair)
                    .font(.system(size: 9))
                    .monospacedDigit()
            }
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
            .opacity(row.below ? 0.55 : 1)
            .frame(height: 12)
            Rectangle()
                .fill(row.lineBelow ? OpeningPanelTokens.Palette.amber : OpeningPanelTicketMetrics.rowLine)
                .frame(height: 1)
        }
    }
}

private extension OpeningPanelSequencePicture {
    var bodyIsComparing: Bool {
        if case .comparing = body { return true }
        return false
    }
}

enum OpeningPanelSequenceLayout {
    static let keyWidth: CGFloat = 54
    static let keyGap: CGFloat = 4
    static let barHeight: CGFloat = 16
    static let undoWidth: CGFloat = 36

    struct Frames: Equatable {
        var column: CGRect
        var bar: CGRect
        var undo: CGRect
        var keys: [CGRect]
        var upperCard: CGRect
        var lowerCard: CGRect
    }

    static func frames(in window: CGRect) -> Frames {
        let keyWidth = min(Self.keyWidth, max(28, window.width * 0.28))
        let columnWidth = max(0, window.width - keyGap - keyWidth)
        let column = CGRect(x: 0, y: 0, width: columnWidth, height: window.height)
        let bar = CGRect(x: 0, y: 0, width: columnWidth, height: barHeight)
        let undo = CGRect(
            x: max(0, columnWidth - undoWidth),
            y: 1,
            width: min(undoWidth, columnWidth),
            height: max(0, barHeight - 2)
        )
        let keyHeight = max(0, (window.height - keyGap * 2) / 3)
        let keys = (0..<3).map { index in
            CGRect(
                x: columnWidth + keyGap,
                y: CGFloat(index) * (keyHeight + keyGap),
                width: keyWidth,
                height: keyHeight
            )
        }
        let bodyY = bar.maxY
        let bodyHeight = max(0, window.height - bodyY)
        let upper = CGRect(x: 0, y: bodyY, width: columnWidth, height: bodyHeight / 2)
        let lower = CGRect(x: 0, y: bodyY + bodyHeight / 2, width: columnWidth, height: bodyHeight / 2)
        return Frames(column: column, bar: bar, undo: undo, keys: keys, upperCard: upper, lowerCard: lower)
    }
}
