//
//  TimetableOccupancyMeter.swift
//  Todo train
//
//  Occupancy as a destination: 駅名標 grammar, not an LED 発車標.
//  Race and 掲示 vs ダイヤ stay visual.
//

import SwiftUI

/// 行先票 as a 駅名標: いま／次 is the index, title is the station, rail is the line band.
struct OccupancyDestinationSign: View {
    enum Surface {
        case grouped
        case inverted
        case cabin
        case station(heat: Bool)
        case glass
    }

    var row: TimetableOccupancyRow
    var surface: Surface
    var compact: Bool = false
    var liveEnd: Date? = nil
    var now: Date = .now
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 8) {
            indexMark
                .padding(.top, compact ? 1 : 2)
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 8) {
                    Text(row.title)
                        .font(destinationFont)
                        .tracking(StationSignMetrics.nameTracking(row.title, compact: compact))
                        .foregroundStyle(destinationInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    timetable
                }
                lineBand
            }
        }
        .padding(.horizontal, isBoarded ? (compact ? 8 : 10) : 0)
        .padding(.vertical, isBoarded ? (compact ? 5 : 7) : 0)
        .modifier(DestinationBoardChrome(surface: surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLine)
        .modifier(DestinationAccessAction(title: actionTitle, action: action))
    }

    @ViewBuilder
    private var timetable: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(row.clock)
                .font(clockFont)
                .monospacedDigit()
                .foregroundStyle(clockInk)
            if let liveEnd {
                Text(
                    timerInterval: liveEnd >= now ? now...liveEnd : now...now,
                    countsDown: true,
                    showsHours: false
                )
                .font(minuteFont)
                .monospacedDigit()
                .foregroundStyle(clockInk)
            } else if let minutes = row.remainingMinutes {
                Text("\(minutes)分")
                    .font(minuteFont)
                    .monospacedDigit()
                    .foregroundStyle(clockInk)
            }
        }
    }

    @ViewBuilder
    private var indexMark: some View {
        Text(row.kind.tense)
            .font((compact ? Font.caption2 : Font.caption).weight(.bold))
            .foregroundStyle(indexForeground)
            .frame(minWidth: compact ? 22 : 26)
            .padding(.vertical, compact ? 3 : 4)
            .background { indexBackground }
    }

    @ViewBuilder
    private var indexBackground: some View {
        let box = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if fillsIndex {
            box.fill(indexFill)
                .overlay { box.strokeBorder(indexStroke, lineWidth: 1) }
        } else {
            box.strokeBorder(indexStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var lineBand: some View {
        if let actionTitle, let action {
            Button(action: action) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(lineColor)
                        .frame(maxWidth: .infinity)
                    Text(actionTitle)
                        .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                        .foregroundStyle(actionOnBarInk)
                        .padding(.horizontal, compact ? 8 : 10)
                        .padding(.vertical, compact ? 3 : 4)
                        .background(actionBarColor)
                }
            }
            .buttonStyle(.plain)
            .frame(height: compact ? 18 : 22)
            .contentShape(Rectangle())
            .clipped()
            .accessibilityHidden(true)
        } else {
            Rectangle()
                .fill(lineColor)
                .frame(height: compact ? 3 : 4)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }

    private var isBoarded: Bool {
        if case .glass = surface { return true }
        if case .station = surface { return false }
        return false
    }

    private var fillsIndex: Bool {
        row.kind == .occupying
    }

    private var destinationFont: Font {
        switch surface {
        case .cabin:
            (compact ? Font.subheadline : Font.title3).weight(.medium)
        default:
            (compact ? Font.subheadline : Font.body).weight(.semibold)
        }
    }

    private var clockFont: Font {
        (compact ? Font.caption : Font.subheadline).weight(.semibold)
    }

    private var minuteFont: Font {
        (compact ? Font.caption2 : Font.caption).weight(.semibold)
    }

    private var destinationInk: Color {
        let base: Color = {
            switch surface {
            case .grouped: TrainTheme.ink
            case .inverted, .cabin: Color.white
            case .glass: Color.primary
            case .station(let heat): heat ? LEDPhosphor.heat : LEDPhosphor.on
            }
        }()
        switch row.kind {
        case .occupying: return base
        case .notice: return base.opacity(0.72)
        case .next: return base.opacity(0.82)
        }
    }

    private var clockInk: Color {
        switch surface {
        case .grouped: TrainTheme.ink
        case .inverted, .cabin: Color.white.opacity(0.82)
        case .glass: Color.primary.opacity(0.82)
        case .station(let heat): (heat ? LEDPhosphor.heat : LEDPhosphor.on).opacity(0.88)
        }
    }

    private var lineColor: Color {
        row.kind == .occupying ? actionBarColor : actionBarColor.opacity(0.5)
    }

    private var actionBarColor: Color {
        switch surface {
        case .station(let heat): heat ? LEDPhosphor.heat : LEDPhosphor.on
        case .grouped, .inverted, .cabin, .glass: TrainTheme.rail
        }
    }

    private var actionOnBarInk: Color {
        switch surface {
        case .station(let heat): heat ? LEDPhosphor.heatHousing : LEDPhosphor.housing
        case .grouped, .inverted, .cabin, .glass: Color.white
        }
    }

    private var indexFill: Color {
        switch surface {
        case .station(let heat): (heat ? LEDPhosphor.heat : LEDPhosphor.on).opacity(0.22)
        case .grouped, .glass: TrainTheme.rail
        case .inverted, .cabin: TrainTheme.rail
        }
    }

    private var indexStroke: Color {
        switch surface {
        case .station: destinationInk
        case .grouped, .glass: fillsIndex ? TrainTheme.rail : destinationInk.opacity(0.7)
        case .inverted, .cabin: fillsIndex ? TrainTheme.rail : Color.white.opacity(0.7)
        }
    }

    private var indexForeground: Color {
        switch surface {
        case .station: destinationInk
        case .grouped, .glass: fillsIndex ? Color.white : destinationInk
        case .inverted, .cabin: Color.white
        }
    }
}

private struct DestinationAccessAction: ViewModifier {
    var title: String?
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        if let title, let action {
            content
                .accessibilityAction(named: title, action)
                .accessibilityHint(TimetableCopy.thisTime)
        } else {
            content
        }
    }
}

private struct DestinationBoardChrome: ViewModifier {
    var surface: OccupancyDestinationSign.Surface

    @ViewBuilder
    func body(content: Content) -> some View {
        switch surface {
        case .glass:
            content.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        default:
            content
        }
    }
}

struct TimetableOccupancyMeter<Accessory: View>: View {
    var rows: [TimetableOccupancyRow]
    var marks: [TimetableOccupancyMark]
    var chrome: Chrome
    var showsRail: Bool
    var compact: Bool
    var accessory: Accessory

    enum Chrome {
        case grouped
        case inverted
        case cabin
    }

    init(
        rows: [TimetableOccupancyRow],
        marks: [TimetableOccupancyMark],
        chrome: Chrome,
        showsRail: Bool = true,
        compact: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.rows = rows
        self.marks = marks
        self.chrome = chrome
        self.showsRail = showsRail
        self.compact = compact
        self.accessory = accessory()
    }

    var body: some View {
        if rows.isEmpty, marks.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: compact ? 6 : 8) {
                VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                    if showsRail, !rows.isEmpty {
                        rail
                    }
                    ForEach(rows) { row in
                        OccupancyDestinationSign(
                            row: row,
                            surface: destinationSurface,
                            compact: compact
                        )
                    }
                }
                accessory
            }
        }
    }

    private var rail: some View {
        GeometryReader { geo in
            let inner = max(geo.size.width - 16, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                Rectangle()
                    .fill(needle)
                    .frame(width: 2, height: 12)
                    .padding(.leading, 6)
                ForEach(marks) { mark in
                    if mark.isCurrent, mark.span > 0 {
                        Capsule()
                            .fill(currentBand)
                            .frame(width: max(6, inner * mark.span), height: 8)
                            .offset(x: 8)
                    } else if !mark.isCurrent {
                        Circle()
                            .fill(nextDot)
                            .frame(width: 7, height: 7)
                            .offset(x: 8 + inner * mark.position)
                    }
                }
            }
        }
        .frame(height: 12)
        .clipped()
        .accessibilityHidden(true)
    }

    private var destinationSurface: OccupancyDestinationSign.Surface {
        switch chrome {
        case .grouped: .grouped
        case .inverted: .inverted
        case .cabin: .cabin
        }
    }

    private var track: Color {
        switch chrome {
        case .grouped: Color.primary.opacity(0.12)
        case .inverted: Color.black.opacity(0.55)
        case .cabin: Color.white.opacity(0.12)
        }
    }

    private var needle: Color {
        switch chrome {
        case .grouped: TrainTheme.rail
        case .inverted: TrainTheme.signalRed
        case .cabin: Color.white.opacity(0.85)
        }
    }

    private var currentBand: Color {
        switch chrome {
        case .grouped: TrainTheme.rail.opacity(0.35)
        case .inverted: TrainTheme.signalAmber
        case .cabin: Color.white.opacity(0.28)
        }
    }

    private var nextDot: Color {
        switch chrome {
        case .grouped, .inverted: TrainTheme.rail
        case .cabin: Color.white.opacity(0.85)
        }
    }
}

extension TimetableOccupancyMeter where Accessory == EmptyView {
    init(
        rows: [TimetableOccupancyRow],
        marks: [TimetableOccupancyMark],
        chrome: Chrome,
        showsRail: Bool = true,
        compact: Bool = false
    ) {
        self.init(
            rows: rows,
            marks: marks,
            chrome: chrome,
            showsRail: showsRail,
            compact: compact
        ) { EmptyView() }
    }
}

#Preview {
    let occupying = TimetableOccupancyRow(
        id: UUID(),
        kind: .occupying,
        clock: "14:00",
        remainingMinutes: 12,
        title: "会議",
        spokenLine: "いま 会議 14:00"
    )
    let next = TimetableOccupancyRow(
        id: UUID(),
        kind: .next,
        clock: "15:30",
        remainingMinutes: 40,
        title: "原稿を書く",
        spokenLine: "次 原稿を書く 15:30"
    )
    VStack(alignment: .leading, spacing: 16) {
        OccupancyDestinationSign(
            row: occupying,
            surface: .glass,
            compact: true,
            actionTitle: "通過",
            action: {}
        )
        OccupancyDestinationSign(
            row: occupying,
            surface: .station(heat: false),
            compact: true,
            actionTitle: "通過",
            action: {}
        )
        OccupancyDestinationSign(
            row: occupying,
            surface: .cabin,
            actionTitle: "通過",
            action: {}
        )
        OccupancyDestinationSign(row: next, surface: .grouped)
            .padding(8)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
    .padding()
    .background(Color.black)
}
