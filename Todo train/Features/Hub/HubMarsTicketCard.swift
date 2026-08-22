//
//  HubMarsTicketCard.swift
//  Todo train
//
//  Full Mars face in the Hub deck. The 改札帯 is printed on the paper;
//  holding the ticket arms 発車. Face tap opens 詳細 only while held.
//

import SwiftUI

struct HubMarsTicketCard: View {
    let ticket: Ticket
    var isLifted: Bool = false
    var canBoard: Bool = false
    var disabledReason: String?
    let onSelect: () -> Void
    var onBoard: () -> Void = {}
    var onOpenDetail: () -> Void = {}

    private var content: MarsTicketContent {
        MarsTicketContent(ticket: ticket)
    }

    var body: some View {
        MarsTicketView(content: content, density: .hub)
            .overlay(alignment: .bottom) {
                HubTicketGateBand(
                    canBoard: canBoard,
                    disabledReason: disabledReason,
                    armed: isLifted,
                    onBoard: onBoard
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: MarsTicketSpec.cornerRadius,
                        bottomTrailingRadius: MarsTicketSpec.cornerRadius,
                        style: .continuous
                    )
                )
            }
            .shadow(
                color: .black.opacity(isLifted ? 0.28 : 0.18),
                radius: isLifted ? 16 : 10,
                y: isLifted ? 8 : 5
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if isLifted {
                    onOpenDetail()
                } else {
                    onSelect()
                }
            }
            .accessibilityElement(children: isLifted ? .contain : .combine)
            .accessibilityAddTraits(isLifted ? [] : .isButton)
            .accessibilityHint(isLifted ? "券面で詳細、改札帯で発車" : "つまんで発車または詳細")
    }
}

#Preview {
    let ticket = Ticket(title: "週次レビュー", estimatedSeconds: 1_500, sortOrder: 0)
    return HubMarsTicketCard(
        ticket: ticket,
        isLifted: true,
        canBoard: true,
        onSelect: {},
        onBoard: {},
        onOpenDetail: {}
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
