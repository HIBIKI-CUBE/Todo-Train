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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ticket.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(ticket.estimatedSeconds / 60)分")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isPaused {
                        Text("停車中")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 8)

            Button("発車") {
                onBoard()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!canBoard)
        }
        .padding(.vertical, 4)
    }
}
