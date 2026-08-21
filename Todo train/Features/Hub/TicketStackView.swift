//
//  TicketStackView.swift
//  Todo train
//
//  Wallet peek deck: full Mars faces stacked (front = bottom = fully visible).
//  Focus morphs via matchedGeometry; deck card stays mounted (opacity 0) so return is continuous.
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
    @Binding var focusedTicketID: UUID?
    var ticketNamespace: Namespace.ID
    /// Hub owns focus entry (animation / chrome policy).
    var onFocusTicket: (UUID) -> Void
    let onBoard: (Ticket) -> Void
    let onOpenDetail: (Ticket) -> Void
    let onDelete: (Ticket) -> Void

    @State private var reportedHeight: CGFloat = 0

    private var orderedIDs: [UUID] {
        tickets.map(\.id)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width - MarsTicketSpec.HubStack.horizontalInset * 2)
            let faceHeight = MarsTicketSpec.height(forWidth: width)
            let peekStep = MarsTicketSpec.HubStack.peekStep
            let yOffsets = TicketStackLayout.offsets(orderedIDs: orderedIDs, peekStep: peekStep)
            let totalH = TicketStackLayout.totalHeight(
                orderedCount: tickets.count,
                faceHeight: faceHeight,
                peekStep: peekStep
            )
            let visibleIDs = Set(yOffsets.keys)
            let anyFocused = focusedTicketID != nil

            ZStack(alignment: .top) {
                ForEach(Array(tickets.enumerated()), id: \.element.id) { index, ticket in
                    if visibleIDs.contains(ticket.id) {
                        let y = yOffsets[ticket.id] ?? 0
                        let isFocused = ticket.id == focusedTicketID
                        let peerFocused = anyFocused && !isFocused
                        // Keep peer tilt; only the flying card is flat (it's opacity-0 on deck).
                        let tilt = isFocused
                            ? 0.0
                            : TicketStackLayout.tiltDegrees(index: index, count: tickets.count)

                        HubMarsTicketCard(
                            ticket: ticket,
                            onSelect: { onFocusTicket(ticket.id) }
                        )
                        .frame(width: width, height: faceHeight, alignment: .top)
                        .matchedGeometryEffect(
                            id: ticket.id,
                            in: ticketNamespace,
                            properties: .frame,
                            anchor: .center,
                            isSource: !isFocused
                        )
                        .opacity(isFocused ? 0 : (peerFocused ? MarsTicketSpec.HubStack.focusPeerOpacity : 1))
                        .allowsHitTesting(!anyFocused)
                        .rotation3DEffect(
                            .degrees(tilt),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .center,
                            perspective: 0.65
                        )
                        .padding(.horizontal, MarsTicketSpec.HubStack.horizontalInset)
                        .offset(y: y)
                        .zIndex(isFocused ? 1_000 : Double(index))
                        .contextMenu {
                            Button("詳細") { onOpenDetail(ticket) }
                            if canBoard {
                                Button("発車") { onBoard(ticket) }
                            }
                            Button("削除", role: .destructive) { onDelete(ticket) }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: totalH, alignment: .top)
            .preference(key: TicketStackHeightKey.self, value: totalH)
        }
        .frame(height: reportedHeight > 0 ? reportedHeight : fallbackHeight)
        .onPreferenceChange(TicketStackHeightKey.self) { reportedHeight = $0 }
        .onChange(of: orderedIDs) { _, ids in
            if let focusedTicketID, !ids.contains(focusedTicketID) {
                self.focusedTicketID = nil
            }
        }
    }

    private var fallbackHeight: CGFloat {
        let width: CGFloat = 320 - MarsTicketSpec.HubStack.horizontalInset * 2
        return TicketStackLayout.totalHeight(
            orderedCount: tickets.count,
            faceHeight: MarsTicketSpec.height(forWidth: max(width, 1))
        )
    }
}

#Preview {
    struct PreviewHost: View {
        @Namespace private var ns
        @State private var focused: UUID?
        private let tickets = [
            Ticket(title: "メモ", estimatedSeconds: 900, sortOrder: 0),
            Ticket(title: "週次レビューの下書き", estimatedSeconds: 1_500, sortOrder: 1),
            Ticket(title: "買い物", estimatedSeconds: 600, sortOrder: 2)
        ]

        var body: some View {
            ScrollView {
                TicketStackView(
                    tickets: tickets,
                    canBoard: true,
                    boardDisabledReason: nil,
                    focusedTicketID: $focused,
                    ticketNamespace: ns,
                    onFocusTicket: { id in
                        withAnimation(MarsTicketSpec.HubStack.focus) {
                            focused = id
                        }
                    },
                    onBoard: { _ in },
                    onOpenDetail: { _ in },
                    onDelete: { _ in }
                )
                .padding(.vertical)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
    return PreviewHost()
}
