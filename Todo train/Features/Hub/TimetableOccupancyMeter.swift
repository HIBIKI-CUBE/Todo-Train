//
//  TimetableOccupancyMeter.swift
//  Todo train
//
//  Occupancy as a 60-minute rail + clock/remaining digits. Not a list. Not a lesson.
//

import SwiftUI

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
                        occupancyRow(row)
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

    private func occupancyRow(_ row: TimetableOccupancyRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 8) {
            Text(row.kind.prefix)
                .font(.caption2.weight(.bold))
                .foregroundStyle(chipForeground(row.kind))
                .padding(.horizontal, compact ? 5 : 6)
                .padding(.vertical, compact ? 1 : 2)
                .background(chipBackground(row.kind), in: Capsule())
            Text(row.clock)
                .font((compact ? Font.caption : Font.body).weight(.semibold).monospacedDigit())
                .foregroundStyle(clockColor)
            if let minutes = row.remainingMinutes {
                Text("\(minutes)分")
                    .font((compact ? Font.caption2 : Font.subheadline).weight(.semibold).monospacedDigit())
                    .foregroundStyle(clockColor)
            }
            Text(row.title)
                .font((compact ? Font.caption2 : Font.caption).weight(.medium))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.spokenLine)
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

    private var clockColor: Color {
        switch chrome {
        case .grouped: TrainTheme.ink
        case .inverted, .cabin: .white
        }
    }

    private var titleColor: Color {
        switch chrome {
        case .grouped: TrainTheme.muted
        case .inverted: Color.white.opacity(0.78)
        case .cabin: FocusPanel.muted
        }
    }

    private func chipForeground(_ kind: TimetableOccupancyKind) -> Color {
        switch chrome {
        case .grouped:
            switch kind {
            case .occupying: Color.white
            case .notice, .next: TrainTheme.ink
            }
        case .inverted, .cabin:
            Color.white
        }
    }

    private func chipBackground(_ kind: TimetableOccupancyKind) -> Color {
        switch chrome {
        case .grouped:
            switch kind {
            case .occupying: TrainTheme.rail
            case .notice: Color.primary.opacity(0.08)
            case .next: Color.primary.opacity(0.10)
            }
        case .inverted:
            switch kind {
            case .occupying: TrainTheme.rail
            case .notice: Color.white.opacity(0.10)
            case .next: Color.white.opacity(0.16)
            }
        case .cabin:
            switch kind {
            case .occupying: TrainTheme.rail
            case .notice: Color.white.opacity(0.08)
            case .next: Color.white.opacity(0.12)
            }
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
