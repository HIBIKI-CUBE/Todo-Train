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
            GeometryReader { proxy in
                clockCanvas(layout: layout, width: proxy.size.width)
            }
            .frame(height: CGFloat(layout.height) + Self.labelSlack)
        }
    }

    private func clockCanvas(layout: DayClockLayout, width: CGFloat) -> some View {
        let laneWidth = max(
            72,
            (width - Self.gutter) / CGFloat(layout.laneCount)
        )
        return ZStack(alignment: .topLeading) {
            hourGrid(layout: layout, width: width)

            ForEach(rides) { ride in
                if let session = sessionByID[ride.id] {
                    rideLayer(
                        ride: ride,
                        session: session,
                        layout: layout,
                        laneWidth: laneWidth
                    )
                }
            }
        }
        .frame(width: width, height: CGFloat(layout.height) + Self.labelSlack, alignment: .topLeading)
    }

    private func hourGrid(layout: DayClockLayout, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(TrainTheme.track)
                .frame(width: 1, height: CGFloat(layout.height))
                .offset(x: Self.gutter - 1)

            ForEach(layout.hourTicks, id: \.self) { tick in
                let y = CGFloat(layout.y(for: tick))
                Rectangle()
                    .fill(TrainTheme.track.opacity(0.7))
                    .frame(width: max(0, width - Self.gutter + 1), height: 1)
                    .offset(x: Self.gutter - 1, y: y)
                Text(Self.timeFormatter.string(from: tick))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: Self.gutter - 8, alignment: .trailing)
                    .offset(y: y - 7)
            }

            if !layout.hourTicks.contains(where: { abs($0.timeIntervalSince(layout.start)) < 1 }) {
                Text(Self.timeFormatter.string(from: layout.start))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.gutter - 8, alignment: .trailing)
                    .offset(y: -7)
            }
        }
        .accessibilityHidden(true)
    }

    private func rideLayer(
        ride: TimelineRide,
        session: WorkSession,
        layout: DayClockLayout,
        laneWidth: CGFloat
    ) -> some View {
        let lane = layout.laneIndex(for: ride.id)
        let x = Self.gutter + CGFloat(lane) * laneWidth
        let startY = CGFloat(layout.y(for: ride.startedAt))
        let endY = CGFloat(layout.y(for: ride.endedAt))
        let barHeight = max(endY - startY, 2)
        let scheduleY = CGFloat(layout.y(for: ride.originalScheduleAt))
        let color = stripColor(for: ride)
        let markers = SessionTimeline.markers(for: ride).filter { marker in
            if case .boarded = marker.kind { return false }
            return true
        }

        return ZStack(alignment: .topLeading) {
            if ride.originalScheduleAt > ride.endedAt {
                Rectangle()
                    .fill(color.opacity(0.25))
                    .frame(width: 2, height: max(0, scheduleY - endY))
                    .offset(x: 3, y: endY)
            }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color.opacity(0.28))
                .frame(width: Self.stripWidth, height: barHeight)
                .offset(y: startY)
                .contextMenu {
                    rideContextMenu(session: session)
                }

            ForEach(ride.pauses, id: \.id) { pause in
                let pauseY = CGFloat(layout.y(for: pause.startedAt))
                let pauseHeight = max(CGFloat(layout.height(from: pause.startedAt, to: pause.endedAt)), 2)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(TrainTheme.signalAmber)
                    .frame(width: Self.stripWidth, height: pauseHeight)
                    .offset(y: pauseY)
            }

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
            .offset(x: Self.stripWidth + 8, y: startY - 2)
            .contextMenu {
                rideContextMenu(session: session)
            }

            ForEach(markers) { marker in
                markerRow(marker)
                    .offset(
                        x: Self.stripWidth + 8,
                        y: CGFloat(layout.y(for: marker.at)) - 7
                    )
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
            .offset(x: Self.stripWidth + 8, y: endY + 12)
        }
        .offset(x: x)
        .frame(width: laneWidth, alignment: .topLeading)
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
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func markerRow(_ marker: TimelineMarker) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(markerColor(marker.kind))
                .frame(width: 6, height: 6)
            Text(SessionTimeline.markerLabel(marker))
                .font(.caption2.weight(.medium))
            Text(Self.timeFormatter.string(from: marker.at))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            if case .extensionStep(_, _, let reason) = marker.kind, let reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

    private static let gutter: CGFloat = 48
    private static let stripWidth: CGFloat = 8
    private static let labelSlack: CGFloat = 36

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
