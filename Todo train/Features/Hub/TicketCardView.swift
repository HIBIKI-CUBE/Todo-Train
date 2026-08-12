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
                VStack(alignment: .leading, spacing: TrainTheme.Space.xs) {
                    Text(ticket.title)
                        .font(TrainTheme.TypeScale.ticketTitle())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: TrainTheme.Space.sm) {
                        Text("\(ticket.estimatedSeconds / 60)分")
                            .font(TrainTheme.TypeScale.meta())
                            .foregroundStyle(.secondary)

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
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("発車") {
                onBoard()
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainTheme.rail)
            .disabled(!canBoard)
        }
    }

    private func dueDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}
