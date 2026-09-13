//
//  TicketStackView.swift
//  Todo train
//
//  Wallet peek deck: full Mars faces stacked (front = bottom = fully visible).
//  Width comes from TicketDeckLayout's proposal this pass — never cached @State.
//  Selection presentation lives on Hub's overlay, not in this stack.
//

import SwiftUI
import UIKit

enum HubTicketCanvas {
    static let spaceName = "hubTicketCanvas"
}

struct TicketStackView: View {
    let tickets: [Ticket]
    let canBoard: Bool
    let boardDisabledReason: String?
    @Binding var focusedTicketID: UUID?
    /// Real card stays in layout but invisible while the issue overlay is the traveling identity.
    var hiddenTicketID: UUID? = nil
    var isPuttingBack: Bool = false
    var onFocusTicket: (UUID) -> Void
    var onDismissFocus: () -> Void
    let onBoard: (Ticket) -> Void
    let onOpenDetail: (Ticket) -> Void
    let onDelete: (Ticket) -> Void
    var zoomNamespace: Namespace.ID? = nil

    private var orderedIDs: [UUID] {
        tickets.map(\.id)
    }

    var body: some View {
        let visibleTickets = tickets
        let anyFocused = focusedTicketID != nil
        let dimPeers = anyFocused && !isPuttingBack

        TicketDeckLayout() {
            ForEach(Array(visibleTickets.enumerated()), id: \.element.id) { index, ticket in
                let isHidden = ticket.id == hiddenTicketID
                let isFocused = ticket.id == focusedTicketID
                let peerFocused = dimPeers && !isFocused && !isHidden
                let tilt = TicketStackLayout.tiltDegrees(index: index, count: visibleTickets.count)

                ticketCard(
                    ticket: ticket,
                    isHidden: isHidden,
                    isFocused: isFocused,
                    peerFocused: peerFocused,
                    blockPeerHits: anyFocused,
                    tilt: tilt
                )
            }
        }
        .onChange(of: orderedIDs) { _, ids in
            if let focusedTicketID, !ids.contains(focusedTicketID) {
                self.focusedTicketID = nil
            }
        }
    }

    @ViewBuilder
    private func ticketCard(
        ticket: Ticket,
        isHidden: Bool,
        isFocused: Bool,
        peerFocused: Bool,
        blockPeerHits: Bool,
        tilt: Double
    ) -> some View {
        HubMarsTicketCard(
            ticket: ticket,
            isLifted: false,
            canBoard: canBoard,
            disabledReason: boardDisabledReason,
            restOffset: .zero,
            allowsDeckSwipe: !isHidden && !isFocused && !blockPeerHits,
            onSelect: { onFocusTicket(ticket.id) },
            onDismissLift: onDismissFocus,
            onDeckSwipeEnded: { action in
                switch action {
                case .board:
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onBoard(ticket)
                case .delete:
                    onDelete(ticket)
                case .snap:
                    break
                }
            }
        )
        .rotation3DEffect(
            .degrees(tilt),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.65
        )
        .opacity(isHidden || isFocused ? 0 : (peerFocused ? MarsTicketSpec.HubStack.focusPeerOpacity : 1))
        .allowsHitTesting(!isHidden && !isFocused && !blockPeerHits)
        .accessibilityHidden(isHidden || isFocused)
        .accessibilityAction(named: "詳細") { onOpenDetail(ticket) }
        .accessibilityAction(named: "削除") { onDelete(ticket) }
        .modifier(DeckBoardAccessibilityAction(enabled: canBoard, onBoard: { onBoard(ticket) }))
        .modifier(
            DeckMatchedTransitionSource(
                ticketID: ticket.id,
                namespace: zoomNamespace,
                enabled: !isHidden && !isFocused
            )
        )
        .contextMenu {
            Button("詳細") { onOpenDetail(ticket) }
            if canBoard {
                Button("発車") { onBoard(ticket) }
            }
            Button("削除", role: .destructive) { onDelete(ticket) }
        }
        .overlay {
            GeometryReader { slotGeo in
                Color.clear.preference(
                    key: TicketSlotFramesKey.self,
                    value: [ticket.id: slotGeo.frame(in: .named(HubTicketCanvas.spaceName))]
                )
            }
        }
    }
}

#Preview {
    struct PreviewHost: View {
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
                    onFocusTicket: { id in
                        withAnimation(MarsTicketSpec.HubStack.focus) {
                            focused = id
                        }
                    },
                    onDismissFocus: {
                        withAnimation(MarsTicketSpec.HubStack.focus) {
                            focused = nil
                        }
                    },
                    onBoard: { _ in },
                    onOpenDetail: { _ in },
                    onDelete: { _ in }
                )
                .padding(.vertical)
            }
            .coordinateSpace(.named(HubTicketCanvas.spaceName))
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
    return PreviewHost()
}

private struct DeckMatchedTransitionSource: ViewModifier {
    let ticketID: UUID
    let namespace: Namespace.ID?
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled, let namespace {
            content.matchedTransitionSource(id: ticketID, in: namespace)
        } else {
            content
        }
    }
}

private struct DeckBoardAccessibilityAction: ViewModifier {
    let enabled: Bool
    let onBoard: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: "発車") { onBoard() }
        } else {
            content
        }
    }
}
