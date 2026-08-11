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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.ticket?.title ?? "不明な切符")
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(HistoryStats.outcomeLabel(session.outcome))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(outcomeColor)

                        Text(durationLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if let ticket = session.ticket {
                    NavigationLink {
                        TicketDetailView(ticket: ticket)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let ticket = session.ticket, let onReissue {
                Button("今日に追加") {
                    onReissue(ticket)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .padding(.leading, 44)
            }

            if session.outcome == .partialDisembark, !children.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(children, id: \.id) { child in
                        NavigationLink {
                            TicketDetailView(ticket: child)
                        } label: {
                            HStack(spacing: 4) {
                                Text("乗り継ぎ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(child.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                if child.isOpen {
                                    Text("Hub")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 2)
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

    private var outcomeColor: Color {
        switch session.outcome {
        case .arrived: .green
        case .partialDisembark: .orange
        case .abandoned: .red
        default: .secondary
        }
    }
}
