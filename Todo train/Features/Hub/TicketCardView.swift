//
//  TicketCardView.swift
//  Todo train
//

import SwiftUI

struct TicketCardView: View {
    let ticket: Ticket
    let canBoard: Bool
    let boardDisabledReason: String?
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
                    }

                    if let progress = TicketProgress.caption(for: ticket) {
                        Text(progress)
                            .font(TrainTheme.TypeScale.meta())
                            .foregroundStyle(TrainTheme.rail)
                            .monospacedDigit()
                    }

                    if showsTags, !ticket.tags.isEmpty {
                        TagChipRow(tags: ticket.tags)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel(ticket.title)
            .accessibilityHint("詳細を開く")

            Button("発車") {
                onBoard()
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainTheme.rail)
            .disabled(!canBoard)
            .accessibilityHint(canBoard ? "フォーカスを開始" : (boardDisabledReason ?? "発車できません"))
        }
        .accessibilityElement(children: .contain)
    }

    private func dueDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}
