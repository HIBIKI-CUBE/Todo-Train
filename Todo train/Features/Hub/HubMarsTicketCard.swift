//
//  HubMarsTicketCard.swift
//  Todo train
//
//  One Mars ticket in the Hub stack: full front with 発車, or peek strip.
//

import SwiftUI

struct HubMarsTicketCard: View {
    let ticket: Ticket
    let isFront: Bool
    let canBoard: Bool
    let boardDisabledReason: String?
    let onBoard: () -> Void
    let onOpenDetail: () -> Void
    let onSelect: () -> Void

    private var content: MarsTicketContent {
        MarsTicketContent(ticket: ticket)
    }

    var body: some View {
        VStack(spacing: 0) {
            MarsTicketView(content: content, density: .hub)
                .shadow(color: .black.opacity(isFront ? 0.18 : 0.1), radius: isFront ? 10 : 4, y: isFront ? 4 : 2)
                .onTapGesture {
                    if isFront {
                        onOpenDetail()
                    } else {
                        onSelect()
                    }
                }

            if isFront {
                boardBar
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var boardBar: some View {
        Button {
            onBoard()
        } label: {
            Text("発車")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: MarsTicketSpec.HubStack.frontBoardBarHeight - 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(TrainTheme.rail)
        .disabled(!canBoard)
        .padding(.horizontal, 2)
        .padding(.top, 6)
        .accessibilityHint(canBoard ? "フォーカスを開始" : (boardDisabledReason ?? "発車できません"))
    }
}

#Preview {
    let ticket = Ticket(title: "週次レビュー", estimatedSeconds: 1_500, sortOrder: 0)
    return HubMarsTicketCard(
        ticket: ticket,
        isFront: true,
        canBoard: true,
        boardDisabledReason: nil,
        onBoard: {},
        onOpenDetail: {},
        onSelect: {}
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
