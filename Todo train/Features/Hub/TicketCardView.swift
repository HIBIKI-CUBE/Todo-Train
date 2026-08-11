//
//  TicketCardView.swift
//  Todo train
//

import SwiftUI

struct TicketCardView: View {
    let ticket: Ticket
    let isPaused: Bool
    let canBoard: Bool
    let onBoard: () -> Void
    var showsTags: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: TrainTheme.Space.md) {
            NavigationLink {
                TicketDetailView(ticket: ticket)
            } label: {
                HStack(alignment: .center, spacing: TrainTheme.Space.md) {
                    Capsule()
                        .fill(isPaused ? TrainTheme.signalAmber : TrainTheme.rail.opacity(0.35))
                        .frame(width: 4, height: 36)

                    VStack(alignment: .leading, spacing: TrainTheme.Space.xs) {
                        Text(ticket.title)
                            .font(TrainTheme.TypeScale.ticketTitle())
                            .foregroundStyle(TrainTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: TrainTheme.Space.sm) {
                            Text("\(ticket.estimatedSeconds / 60)分")
                                .font(TrainTheme.TypeScale.meta())
                                .foregroundStyle(TrainTheme.muted)

                            if let dueDate = ticket.dueDate {
                                SignalBadge(kind: .due, customLabel: dueDateLabel(dueDate))
                            }

                            if isPaused {
                                SignalBadge(kind: .paused)
                            }
                        }

                        if showsTags, !ticket.tags.isEmpty {
                            TagChipRow(tags: ticket.tags)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button("発車") {
                onBoard()
            }
            .buttonStyle(DepartButtonStyle(enabled: canBoard))
            .disabled(!canBoard)
        }
        .ticketSurface(emphasized: isPaused)
    }

    private func dueDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}
