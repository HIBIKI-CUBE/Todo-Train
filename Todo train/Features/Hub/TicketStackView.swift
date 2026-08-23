//
//  TicketStackView.swift
//  Todo train
//
//  Wallet peek deck: full Mars faces stacked (front = bottom = fully visible).
//  Selection presentation lives on Hub's overlay, not in this stack.
//

import SwiftUI

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
    /// Parent-measured column width so the first layout pass is not a 390pt guess.
    var proposedWidth: CGFloat = 0

    @State private var stackWidth: CGFloat = 0

    private var orderedIDs: [UUID] {
        tickets.map(\.id)
    }

    var body: some View {
        let containerWidth = TrainLayout.resolvedTicketContainerWidth(
            measured: stackWidth,
            proposed: proposedWidth
        )
        let face = TrainLayout.ticketFaceSize(containerWidth: containerWidth)
        let peekStep = MarsTicketSpec.HubStack.peekStep
        let yOffsets = TicketStackLayout.offsets(orderedIDs: orderedIDs, peekStep: peekStep)
        let totalH = TicketStackLayout.totalHeight(
            orderedCount: tickets.count,
            faceHeight: face.height,
            peekStep: peekStep
        )
        let visibleIDs = Set(yOffsets.keys)
        let visibleTickets = tickets.filter { visibleIDs.contains($0.id) }
        let anyFocused = focusedTicketID != nil
        let dimPeers = anyFocused && !isPuttingBack

        ZStack(alignment: .top) {
            ForEach(Array(visibleTickets.enumerated()), id: \.element.id) { index, ticket in
                let y = yOffsets[ticket.id] ?? 0
                let isHidden = ticket.id == hiddenTicketID
                let isFocused = ticket.id == focusedTicketID
                let peerFocused = dimPeers && !isFocused && !isHidden
                let tilt = TicketStackLayout.tiltDegrees(index: index, count: visibleTickets.count)

                ticketCard(
                    ticket: ticket,
                    index: index,
                    y: y,
                    width: face.width,
                    faceHeight: face.height,
                    isHidden: isHidden,
                    isFocused: isFocused,
                    peerFocused: peerFocused,
                    blockPeerHits: anyFocused,
                    tilt: tilt
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: containerWidth > 1 ? totalH : 0, alignment: .top)
        // ScrollView sizes content to children; pin to the column, not the last face width.
        .containerRelativeFrame(.horizontal, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, newWidth in
            if abs(stackWidth - newWidth) > 0.5 {
                stackWidth = newWidth
            }
        }
        .onChange(of: proposedWidth) { _, newWidth in
            if newWidth > 1, stackWidth > newWidth + 1 {
                stackWidth = newWidth
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
        index: Int,
        y: CGFloat,
        width: CGFloat,
        faceHeight: CGFloat,
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
            onSelect: { onFocusTicket(ticket.id) },
            onDismissLift: onDismissFocus
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
        .contextMenu {
            Button("詳細") { onOpenDetail(ticket) }
            if canBoard {
                Button("発車") { onBoard(ticket) }
            }
            Button("削除", role: .destructive) { onDelete(ticket) }
        }
        .frame(width: width, height: faceHeight, alignment: .top)
        .overlay {
            GeometryReader { slotGeo in
                Color.clear.preference(
                    key: TicketSlotFramesKey.self,
                    value: [ticket.id: slotGeo.frame(in: .named(HubTicketCanvas.spaceName))]
                )
            }
        }
        .padding(.horizontal, MarsTicketSpec.HubStack.horizontalInset)
        .padding(.top, y)
        .zIndex(Double(index))
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
