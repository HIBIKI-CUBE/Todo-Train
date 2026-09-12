//
//  HistoryDayClockView.swift
//  Todo train
//
//  One calendar day on a wall-clock canvas. Idle minutes use the same
//  points-per-minute as riding — they are not folded. Rides are calendar
//  blocks; markers live in the ride sheet.
//

import SwiftUI

struct HistoryDayClockView: View {
    let sessions: [WorkSession]
    var day: Date? = nil
    var sharedLayout: DayClockLayout? = nil
    var density: HistoryRideDensity = .day
    var showsGutter: Bool = true
    var minHeight: CGFloat = 0
    var onSelect: (WorkSession) -> Void
    var onReissue: ((Ticket) -> Void)?
    var onDelete: (WorkSession) -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        if let prepared {
            HStack(alignment: .top, spacing: 0) {
                if showsGutter {
                    HistoryTimeGutter(layout: prepared.layout, density: density)
                }
                laneStack(layout: prepared.layout, rides: prepared.rides)
            }
            .padding(.top, Self.topSlack)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: canvasHeight(prepared.layout) + Self.topSlack, alignment: .top)
            .clipped()
            .accessibilityElement(children: .contain)
        }
    }

    private var prepared: PreparedDay? {
        let clipped: [TimelineRide] = {
            let raw = SessionTimeline.rides(from: sessions)
            guard let day else { return raw }
            return raw.compactMap { SessionTimeline.clip($0, toDay: day, calendar: calendar) }
        }()

        if let sharedLayout {
            let reference = calendar.startOfDay(for: sharedLayout.start)
            let projected = clipped.map {
                SessionTimeline.project($0, onto: reference, calendar: calendar)
            }
            return PreparedDay(
                layout: SessionTimeline.layoutForDay(rides: projected, shared: sharedLayout),
                rides: projected
            )
        }

        guard let layout = SessionTimeline.layout(
            rides: clipped,
            calendar: calendar,
            minHeight: Double(max(0, minHeight - Self.topSlack))
        ) else {
            return nil
        }
        return PreparedDay(layout: layout, rides: clipped)
    }

    private func canvasHeight(_ layout: DayClockLayout) -> CGFloat {
        CGFloat(layout.height)
    }

    private func laneStack(layout: DayClockLayout, rides: [TimelineRide]) -> some View {
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        return ZStack(alignment: .topLeading) {
            HourGridCanvas(layout: layout, density: density)
                .frame(maxWidth: .infinity)
                .frame(height: canvasHeight(layout))
                .allowsHitTesting(false)

            HStack(alignment: .top, spacing: density.laneSpacing) {
                ForEach(0..<layout.laneCount, id: \.self) { lane in
                    laneColumn(lane, layout: layout, rides: rides, sessionByID: sessionByID)
                }
            }

            ForEach(rides.filter { SessionTimeline.rideIsIsolated($0, among: rides) }) { ride in
                if let session = sessionByID[ride.id] {
                    rideBlock(
                        ride: ride,
                        session: session,
                        layout: layout,
                        laneRides: [ride]
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: canvasHeight(layout), alignment: .topLeading)
    }

    private func laneColumn(
        _ lane: Int,
        layout: DayClockLayout,
        rides: [TimelineRide],
        sessionByID: [UUID: WorkSession]
    ) -> some View {
        let laneRides = rides.filter {
            layout.laneIndex(for: $0.id) == lane && !SessionTimeline.rideIsIsolated($0, among: rides)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(laneRides) { ride in
                if let session = sessionByID[ride.id] {
                    rideBlock(ride: ride, session: session, layout: layout, laneRides: laneRides)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: canvasHeight(layout), alignment: .topLeading)
    }

    private func rideBlock(
        ride: TimelineRide,
        session: WorkSession,
        layout: DayClockLayout,
        laneRides: [TimelineRide]
    ) -> some View {
        let startY = CGFloat(layout.y(for: ride.startedAt))
        let barHeight = max(CGFloat(layout.height(from: ride.startedAt, to: ride.endedAt)), density.minBlockHeight)
        let color = Self.stripColor(for: ride)
        let ghostUntil = ghostEnd(for: ride, in: laneRides, layout: layout)

        return ZStack(alignment: .topLeading) {
            if density.showsGhost, ghostUntil > ride.endedAt {
                let ghostY = CGFloat(layout.y(for: ride.endedAt))
                let ghostHeight = max(CGFloat(layout.height(from: ride.endedAt, to: ghostUntil)), 4)
                RoundedRectangle(cornerRadius: density.blockRadius, style: .continuous)
                    .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: density.blockRadius, style: .continuous)
                            .fill(color.opacity(0.08))
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: ghostHeight)
                    .padding(.top, ghostY)
                    .accessibilityHidden(true)
            }

            Button {
                onSelect(session)
            } label: {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: density.blockRadius, style: .continuous)
                        .fill(color.opacity(density == .week ? 0.28 : 0.18))

                    HStack(spacing: 0) {
                        Capsule()
                            .fill(color)
                            .frame(width: density.accentWidth)
                            .padding(.vertical, density == .week ? 2 : 6)
                            .padding(.leading, density == .week ? 3 : 6)

                        blockLabel(ride: ride, height: barHeight)
                            .padding(.horizontal, density == .week ? 4 : 8)
                            .padding(.vertical, density.labelVerticalPadding(barHeight: barHeight))
                    }

                    if density.showsPauseBands {
                        pauseBands(ride: ride, layout: layout, startY: startY)
                    }
                    if density.showsScheduleHairline {
                        scheduleHairline(ride: ride, layout: layout, startY: startY)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: barHeight, maxHeight: barHeight, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: density.blockRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(height: barHeight, alignment: .top)
            .padding(.top, startY)
            .contextMenu {
                rideContextMenu(session: session)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SessionTimeline.spokenSummary(for: ride, timeFormatter: Self.timeFormatter))
            .accessibilityHint("詳細を表示")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "削除") {
                onDelete(session)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func blockLabel(ride: TimelineRide, height: CGFloat) -> some View {
        switch density {
        case .week:
            if height >= 16 {
                Text(ride.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: height, alignment: .topLeading)
            }
        case .compact:
            ViewThatFits(in: .vertical) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(ride.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.timeFormatter.string(from: ride.startedAt))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(ride.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: height, alignment: .topLeading)
        case .day:
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ride.title)
                            .font(TrainTheme.TypeScale.ticketTitle())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        HistoryOutcomeBadge(outcome: ride.outcome, punctuality: ride.punctuality)
                    }
                    Text(timeRangeText(for: ride))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ride.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.timeFormatter.string(from: ride.startedAt))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(ride.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: height, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func pauseBands(ride: TimelineRide, layout: DayClockLayout, startY: CGFloat) -> some View {
        ForEach(ride.pauses, id: \.id) { pause in
            let y = CGFloat(layout.y(for: pause.startedAt)) - startY
            let height = max(CGFloat(layout.height(from: pause.startedAt, to: pause.endedAt)), 3)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(TrainTheme.signalAmber.opacity(0.38))
                .frame(maxWidth: .infinity)
                .frame(height: height, alignment: .top)
                .padding(.top, y)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func scheduleHairline(ride: TimelineRide, layout: DayClockLayout, startY: CGFloat) -> some View {
        if ride.originalScheduleAt > ride.startedAt, ride.originalScheduleAt < ride.endedAt {
            Rectangle()
                .fill(Color.primary.opacity(0.22))
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.top, CGFloat(layout.y(for: ride.originalScheduleAt)) - startY)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func rideContextMenu(session: WorkSession) -> some View {
        Button("詳細") {
            onSelect(session)
        }
        if let ticket = session.ticket, let onReissue {
            Button("今日に追加") {
                onReissue(ticket)
            }
        }
        Button("削除", role: .destructive) {
            onDelete(session)
        }
    }

    private func timeRangeText(for ride: TimelineRide) -> String {
        "\(Self.timeFormatter.string(from: ride.startedAt))–\(Self.timeFormatter.string(from: ride.endedAt))"
    }

    private func ghostEnd(
        for ride: TimelineRide,
        in laneRides: [TimelineRide],
        layout: DayClockLayout
    ) -> Date {
        let nextStart = laneRides
            .filter { $0.startedAt >= ride.endedAt && $0.id != ride.id }
            .map(\.startedAt)
            .min()
        let cap = nextStart ?? layout.end
        return min(max(ride.originalScheduleAt, ride.endedAt), cap)
    }

    static func stripColor(for ride: TimelineRide) -> Color {
        switch ride.outcome {
        case .abandoned:
            return TrainTheme.signalRed
        case .partialDisembark:
            return TrainTheme.signalAmber
        case .arrived:
            switch ride.punctuality {
            case .onTime, .early:
                return TrainTheme.signalGreen
            default:
                return TrainTheme.rail
            }
        default:
            return TrainTheme.rail
        }
    }

    static let topSlack: CGFloat = 10

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct PreparedDay {
    var layout: DayClockLayout
    var rides: [TimelineRide]
}

private extension HistoryRideDensity {
    func labelVerticalPadding(barHeight: CGFloat) -> CGFloat {
        switch self {
        case .week:
            return 2
        case .compact:
            return 4
        case .day:
            return barHeight < 72 ? 4 : 8
        }
    }
}

struct HistoryTimeGutter: View {
    let layout: DayClockLayout
    var density: HistoryRideDensity = .day

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(layout.hourTicks, id: \.self) { tick in
                if shouldLabel(tick) {
                    Text(label(tick))
                        .font(density == .week ? Font.caption2.weight(.semibold).monospacedDigit() : Font.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .offset(y: CGFloat(layout.y(for: tick)) - (density == .week ? 6 : 8))
                }
            }
        }
        .frame(width: density.gutterWidth, height: CGFloat(layout.height), alignment: .topTrailing)
        .padding(.trailing, density.gutterTrailing)
        .accessibilityHidden(true)
    }

    private func shouldLabel(_ tick: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: tick)
        return hour % density.hourLabelStride == 0
    }

    private func label(_ tick: Date) -> String {
        density == .week ? Self.hourFormatter.string(from: tick) : Self.timeFormatter.string(from: tick)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H"
        return formatter
    }()
}

private struct HourGridCanvas: View {
    let layout: DayClockLayout
    var density: HistoryRideDensity = .day

    var body: some View {
        Canvas { context, size in
            let height = CGFloat(layout.height)

            for tick in layout.hourTicks {
                let y = CGFloat(layout.y(for: tick))
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(TrainTheme.track), lineWidth: 1)

                if density.showsHalfHourLines {
                    let halfY = y + CGFloat(layout.pointsPerMinute * 30)
                    if halfY < height - 0.5 {
                        var half = Path()
                        half.move(to: CGPoint(x: 0, y: halfY))
                        half.addLine(to: CGPoint(x: size.width, y: halfY))
                        context.stroke(half, with: .color(TrainTheme.track.opacity(0.45)), lineWidth: 0.5)
                    }
                }
            }

            if let last = layout.hourTicks.last, last < layout.end {
                let y = CGFloat(layout.height)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(TrainTheme.track), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
