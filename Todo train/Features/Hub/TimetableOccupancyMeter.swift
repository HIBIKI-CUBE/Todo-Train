//
//  TimetableOccupancyMeter.swift
//  Todo train
//
//  Occupancy as a destination: いま／次 and title are words; clock is digits.
//  Race and 掲示 vs ダイヤ stay visual.
//

import SwiftUI

/// 行先票. Title is the destination; clock is the timetable.
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
        HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 8) {
            Text(row.kind.tense)
                .font((compact ? Font.caption2 : Font.caption).weight(.bold))
                .foregroundStyle(destinationInk)
            Text(row.title)
                .font(destinationFont)
                .foregroundStyle(destinationInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
            timetable
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .foregroundStyle(actionInk)
                    .buttonStyle(.plain)
                    .accessibilityHint(TimetableCopy.thisTime)
            }
        }
        .padding(.horizontal, isBoarded ? 10 : 0)
        .padding(.vertical, isBoarded ? 7 : 0)
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

    private var isBoarded: Bool {
        if case .glass = surface { return true }
        if case .station = surface { return false }
        return false
    }

    private var destinationFont: Font {
        (compact ? Font.subheadline : Font.body).weight(.semibold)
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

    private var actionInk: Color {
        destinationInk
    }
}

private struct DestinationAccessAction: ViewModifier {
    var title: String?
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        if let title, let action {
            content.accessibilityAction(named: title, action)
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
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
