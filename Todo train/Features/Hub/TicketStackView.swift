//
//  TicketStackView.swift
//  Todo train
//
//  Wallet-style peek stack of Mars tickets for Hub.
//

import SwiftUI

private struct TicketStackHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TicketStackView: View {
    let tickets: [Ticket]
    let canBoard: Bool
    let boardDisabledReason: String?
    var highlightedTicketID: UUID?
    let onBoard: (Ticket) -> Void
    let onOpenDetail: (Ticket) -> Void
    let onDelete: (Ticket) -> Void

    @State private var frontID: UUID?
    @State private var reportedHeight: CGFloat = 0

    private var orderedIDs: [UUID] {
        tickets.map(\.id)
    }

    private var resolvedFrontID: UUID? {
        if let frontID, tickets.contains(where: { $0.id == frontID }) {
            return frontID
        }
        if let highlightedTicketID, tickets.contains(where: { $0.id == highlightedTicketID }) {
            return highlightedTicketID
        }
        return tickets.first?.id
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width - MarsTicketSpec.HubStack.horizontalInset * 2)
            let ticketHeight = MarsTicketSpec.height(forWidth: width)
            let peekStep = MarsTicketSpec.HubStack.peekStep(visibleCount: tickets.count)
            let front = resolvedFrontID
            let yOffsets = TicketStackLayout.offsets(
                orderedIDs: orderedIDs,
                frontID: front,
                ticketHeight: ticketHeight,
                peekStep: peekStep
            )
            let totalH = TicketStackLayout.totalHeight(
                orderedCount: tickets.count,
                ticketHeight: ticketHeight,
                peekStep: peekStep
            )

            ZStack(alignment: .top) {
                ForEach(tickets, id: \.id) { ticket in
                    let isFront = ticket.id == front
                    let y = yOffsets[ticket.id] ?? 0
                    card(
                        ticket: ticket,
                        isFront: isFront,
                        width: width,
                        ticketHeight: ticketHeight
                    )
                    .offset(y: y)
                    .zIndex(isFront ? 1_000 : Double(500 - Int(y)))
                }
            }
            .frame(width: geo.size.width, height: totalH, alignment: .top)
            .preference(key: TicketStackHeightKey.self, value: totalH)
        }
        .frame(height: reportedHeight > 0 ? reportedHeight : fallbackHeight)
        .onPreferenceChange(TicketStackHeightKey.self) { reportedHeight = $0 }
        .onChange(of: highlightedTicketID) { _, newValue in
            guard let newValue, tickets.contains(where: { $0.id == newValue }) else { return }
            withAnimation(MarsTicketSpec.HubStack.bringToFront) {
                frontID = newValue
            }
        }
        .onChange(of: orderedIDs) { _, ids in
            if let frontID, !ids.contains(frontID) {
                self.frontID = ids.first
            } else if frontID == nil {
                frontID = ids.first
            }
        }
        .onAppear {
            if frontID == nil {
                frontID = resolvedFrontID
            }
        }
    }

    private var fallbackHeight: CGFloat {
        TicketStackLayout.totalHeight(
            orderedCount: tickets.count,
            ticketHeight: MarsTicketSpec.height(forWidth: 320)
        )
    }

    @ViewBuilder
    private func card(
        ticket: Ticket,
        isFront: Bool,
        width: CGFloat,
        ticketHeight: CGFloat
    ) -> some View {
        let fullHeight = ticketHeight + (isFront ? MarsTicketSpec.HubStack.frontBoardBarHeight : 0)
        let visibleHeight = isFront ? fullHeight : MarsTicketSpec.HubStack.peekHeight

        HubMarsTicketCard(
            ticket: ticket,
            isFront: isFront,
            canBoard: canBoard,
            boardDisabledReason: boardDisabledReason,
            onBoard: { onBoard(ticket) },
            onOpenDetail: { onOpenDetail(ticket) },
            onSelect: {
                withAnimation(MarsTicketSpec.HubStack.bringToFront) {
                    frontID = ticket.id
                }
            }
        )
        .frame(width: width, height: fullHeight, alignment: .top)
        .frame(height: visibleHeight, alignment: .top)
        .clipped()
        .padding(.horizontal, MarsTicketSpec.HubStack.horizontalInset)
        .contextMenu {
            Button("詳細") { onOpenDetail(ticket) }
            if canBoard {
                Button("発車") { onBoard(ticket) }
            }
            Button("削除", role: .destructive) { onDelete(ticket) }
        }
    }
}

#Preview {
    let a = Ticket(title: "メモ", estimatedSeconds: 900, sortOrder: 0)
    let b = Ticket(title: "週次レビューの下書き", estimatedSeconds: 1_500, sortOrder: 1)
    let c = Ticket(title: "買い物", estimatedSeconds: 600, sortOrder: 2)
    return ScrollView {
        TicketStackView(
            tickets: [a, b, c],
            canBoard: true,
            boardDisabledReason: nil,
            onBoard: { _ in },
            onOpenDetail: { _ in },
            onDelete: { _ in }
        )
        .padding(.vertical)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
