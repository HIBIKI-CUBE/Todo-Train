//
//  HistorySessionRow.swift
//  Todo train
//

import SwiftUI

struct HistorySessionRow: View {
    let session: WorkSession
    var onReissue: ((Ticket) -> Void)?

    private var children: [Ticket] {
        session.ticket?.childLineages.compactMap(\.child) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(timeLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.ticket?.title ?? "不明な切符")
                        .font(TrainTheme.TypeScale.ticketTitle())
                        .lineLimit(1)

                    HStack(spacing: TrainTheme.Space.sm) {
                        outcomeBadge
                        Text(durationLabel)
                            .font(TrainTheme.TypeScale.meta())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if let ticket = session.ticket {
                    NavigationLink {
                        TicketDetailView(ticket: ticket)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let ticket = session.ticket, let onReissue {
                Button("今日に追加") {
                    onReissue(ticket)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(TrainTheme.rail)
                .padding(.leading, 44)
            }

            if session.outcome == .partialDisembark, !children.isEmpty {
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
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var outcomeBadge: some View {
        switch session.outcome {
        case .arrived:
            switch Punctuality.classify(session) {
            case .onTime:
                SignalBadge(kind: .onTime)
            case .early:
                SignalBadge(kind: .early)
            default:
                SignalBadge(kind: .arrived)
            }
        case .partialDisembark:
            SignalBadge(kind: .paused, customLabel: "途中下車")
        case .abandoned:
            SignalBadge(kind: .abandoned)
        default:
            Text(HistoryStats.outcomeLabel(session.outcome))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainTheme.muted)
        }
    }

    private var timeLabel: String {
        guard let endedAt = session.endedAt else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: endedAt)
    }

    private var durationLabel: String {
        let actual = Int(session.accumulatedActiveSeconds / 60)
        let estimate = session.estimatedSecondsAtStart / 60
        return "\(actual)分/\(estimate)分"
    }
}
