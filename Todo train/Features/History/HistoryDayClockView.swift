//
//  HistoryDayClockView.swift
//  Todo train
//
//  One calendar day on a wall-clock canvas. Idle minutes use the same
//  points-per-minute as riding — they are not folded.
//

import SwiftUI

struct HistoryDayClockView: View {
    let sessions: [WorkSession]
    var onReissue: ((Ticket) -> Void)?
    var onDelete: (WorkSession) -> Void

    private var rides: [TimelineRide] {
        SessionTimeline.rides(from: sessions)
    }

    private var sessionByID: [UUID: WorkSession] {
        Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    var body: some View {
        if let layout = SessionTimeline.layout(rides: rides) {
            HStack(alignment: .top, spacing: 0) {
                timeGutter(layout: layout)
                laneStack(layout: layout)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: canvasHeight(layout), alignment: .top)
            .clipped()
            .accessibilityElement(children: .contain)
        }
    }

    private func canvasHeight(_ layout: DayClockLayout) -> CGFloat {
        CGFloat(layout.height) + Self.labelSlack
    }

    private func timeGutter(layout: DayClockLayout) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(layout.hourTicks, id: \.self) { tick in
                Text(Self.timeFormatter.string(from: tick))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .padding(.top, CGFloat(layout.y(for: tick)))
            }

            if !layout.hourTicks.contains(where: { abs($0.timeIntervalSince(layout.start)) < 1 }) {
                Text(Self.timeFormatter.string(from: layout.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.gutter, height: canvasHeight(layout), alignment: .topTrailing)
        .padding(.trailing, 8)
        .accessibilityHidden(true)
    }

    private func laneStack(layout: DayClockLayout) -> some View {
        ZStack(alignment: .topLeading) {
            HourGridCanvas(layout: layout, rides: rides)
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(layout.height))
                .allowsHitTesting(false)

            HStack(alignment: .top, spacing: Self.laneSpacing) {
                ForEach(0..<layout.laneCount, id: \.self) { lane in
                    laneColumn(lane, layout: layout)
                }
            }
            .padding(.leading, Self.stripWidth + 10)
        }
        .frame(maxWidth: .infinity, minHeight: canvasHeight(layout), alignment: .topLeading)
    }

    private func laneColumn(_ lane: Int, layout: DayClockLayout) -> some View {
        let laneRides = rides.filter { layout.laneIndex(for: $0.id) == lane }
        return ZStack(alignment: .topLeading) {
            ForEach(laneRides) { ride in
                if let session = sessionByID[ride.id] {
                    rideLabels(ride: ride, session: session, layout: layout)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: canvasHeight(layout), alignment: .topLeading)
    }

    private func rideLabels(
        ride: TimelineRide,
        session: WorkSession,
        layout: DayClockLayout
    ) -> some View {
        let startY = CGFloat(layout.y(for: ride.startedAt))
        let endY = CGFloat(layout.y(for: ride.endedAt))
        let markers = SessionTimeline.markers(for: ride).filter { marker in
            if case .boarded = marker.kind { return false }
            return true
        }

        return ZStack(alignment: .topLeading) {
            Group {
                if let ticket = session.ticket {
                    NavigationLink {
                        TicketDetailView(ticket: ticket)
                    } label: {
                        titleBlock(for: ride)
                    }
                    .buttonStyle(.plain)
                } else {
                    titleBlock(for: ride)
                }
            }
            .padding(.top, startY)
            .contextMenu {
                rideContextMenu(session: session)
            }

            ForEach(markers) { marker in
                markerRow(marker)
                    .padding(.top, CGFloat(layout.y(for: marker.at)))
            }

            VStack(alignment: .leading, spacing: 6) {
                if let ticket = session.ticket, let onReissue {
                    Button("今日に追加") {
                        onReissue(ticket)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(TrainTheme.rail)
                }
                transferLinks(session: session)
            }
            .padding(.top, endY + 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SessionTimeline.spokenSummary(for: ride, timeFormatter: Self.timeFormatter))
        .accessibilityAction(named: "削除") {
            onDelete(session)
        }
    }

    @ViewBuilder
    private func rideContextMenu(session: WorkSession) -> some View {
        if let ticket = session.ticket {
            NavigationLink {
                TicketDetailView(ticket: ticket)
            } label: {
                Label("切符の詳細", systemImage: "ticket")
            }
            if let onReissue {
                Button("今日に追加") {
                    onReissue(ticket)
                }
            }
        }
        Button("削除", role: .destructive) {
            onDelete(session)
        }
    }

    private func titleBlock(for ride: TimelineRide) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ride.title)
                    .font(TrainTheme.TypeScale.ticketTitle())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HistoryOutcomeBadge(outcome: ride.outcome, punctuality: ride.punctuality)
            }
            Text("発車 \(Self.timeFormatter.string(from: ride.startedAt))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func markerRow(_ marker: TimelineMarker) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(markerColor(marker.kind))
                .frame(width: 8, height: 8)
            Text(SessionTimeline.markerLabel(marker))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(Self.timeFormatter.string(from: marker.at))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if case .extensionStep(_, _, let reason) = marker.kind, let reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func transferLinks(session: WorkSession) -> some View {
        if session.outcome == .partialDisembark {
            let children = session.ticket?.childLineages.compactMap(\.child) ?? []
            VStack(alignment: .leading, spacing: 4) {
                ForEach(children, id: \.id) { child in
                    NavigationLink {
                        TicketDetailView(ticket: child)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("乗り継ぎ")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(child.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if child.isOpen {
                                SignalBadge(kind: .inService, customLabel: "Hub")
                            }
                        }
                    }
                }
            }
        }
    }

    private func markerColor(_ kind: TimelineMarkerKind) -> Color {
        switch kind {
        case .boarded:
            return TrainTheme.rail
        case .originalSchedule:
            return TrainTheme.muted
        case .extensionStep:
            return TrainTheme.rail
        case .pause:
            return TrainTheme.signalAmber
        case .arrived:
            return TrainTheme.signalGreen
        case .partialDisembark:
            return TrainTheme.signalAmber
        case .abandoned:
            return TrainTheme.signalRed
        }
    }

    private static let gutter: CGFloat = 52
    static let stripWidth: CGFloat = 12
    private static let laneSpacing: CGFloat = 8
    private static let labelSlack: CGFloat = 48

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct HourGridCanvas: View {
    let layout: DayClockLayout
    let rides: [TimelineRide]

    var body: some View {
        Canvas { context, size in
            let height = CGFloat(layout.height)
            let laneWidth = max(1, size.width / CGFloat(layout.laneCount))

            var spine = Path()
            spine.move(to: CGPoint(x: HistoryDayClockView.stripWidth / 2, y: 0))
            spine.addLine(to: CGPoint(x: HistoryDayClockView.stripWidth / 2, y: height))
            context.stroke(spine, with: .color(TrainTheme.track), lineWidth: 2)

            for tick in layout.hourTicks {
                let y = CGFloat(layout.y(for: tick))
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(TrainTheme.track.opacity(0.8)), lineWidth: 1)
            }

            for ride in rides {
                let lane = CGFloat(layout.laneIndex(for: ride.id))
                let x = lane * laneWidth
                let startY = CGFloat(layout.y(for: ride.startedAt))
                let barHeight = max(CGFloat(layout.height(from: ride.startedAt, to: ride.endedAt)), 3)
                let color = stripColor(for: ride)
                let bar = CGRect(
                    x: x,
                    y: startY,
                    width: HistoryDayClockView.stripWidth,
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: bar, cornerRadius: 3),
                    with: .color(color.opacity(0.55))
                )

                if ride.originalScheduleAt > ride.endedAt {
                    let endY = CGFloat(layout.y(for: ride.endedAt))
                    let scheduleY = CGFloat(layout.y(for: ride.originalScheduleAt))
                    var ghost = Path()
                    ghost.move(to: CGPoint(x: x + HistoryDayClockView.stripWidth / 2, y: endY))
                    ghost.addLine(to: CGPoint(x: x + HistoryDayClockView.stripWidth / 2, y: scheduleY))
                    context.stroke(ghost, with: .color(color.opacity(0.45)), lineWidth: 2)
                }

                for pause in ride.pauses {
                    let pauseRect = CGRect(
                        x: x,
                        y: CGFloat(layout.y(for: pause.startedAt)),
                        width: HistoryDayClockView.stripWidth,
                        height: max(CGFloat(layout.height(from: pause.startedAt, to: pause.endedAt)), 3)
                    )
                    context.fill(
                        Path(roundedRect: pauseRect, cornerRadius: 3),
                        with: .color(TrainTheme.signalAmber)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func stripColor(for ride: TimelineRide) -> Color {
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
}
