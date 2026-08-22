//
//  TicketStackView.swift
//  Todo train
//
//  Wallet peek deck: full Mars faces stacked (front = bottom = fully visible).
//  Focus picks up the same card (tilt flattens, offset to cabin center). No copy.
//

import SwiftUI

enum HubTicketCanvas {
    static let spaceName = "hubTicketCanvas"
}

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
    var canvasSize: CGSize
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
            let stackFrame = geo.frame(in: .named(HubTicketCanvas.spaceName))
            let destination = TicketStackLayout.liftDestination(
                stackFrame: stackFrame,
                canvasSize: canvasSize.width > 0 ? canvasSize : geo.size
            )

            ZStack(alignment: .top) {
                ForEach(Array(tickets.enumerated()), id: \.element.id) { index, ticket in
                    if visibleIDs.contains(ticket.id) {
                        let y = yOffsets[ticket.id] ?? 0
                        let isFocused = ticket.id == focusedTicketID
                        let peerFocused = anyFocused && !isFocused
                        let tilt = isFocused
                            ? 0.0
                            : TicketStackLayout.tiltDegrees(index: index, count: tickets.count)
                        let slot = TicketStackLayout.slotCenter(
                            stackFrame: stackFrame,
                            horizontalInset: MarsTicketSpec.HubStack.horizontalInset,
                            faceWidth: width,
                            faceHeight: faceHeight,
                            slotTopY: y
                        )
                        let lift = isFocused
                            ? TicketStackLayout.liftOffset(from: slot, to: destination)
                            : .zero

                        HubMarsTicketCard(
                            ticket: ticket,
                            isLifted: isFocused,
                            canBoard: canBoard,
                            disabledReason: boardDisabledReason,
                            onSelect: { onFocusTicket(ticket.id) },
                            onBoard: { onBoard(ticket) },
                            onOpenDetail: { onOpenDetail(ticket) }
                        )
                        .frame(width: width, height: faceHeight, alignment: .top)
                        .opacity(peerFocused ? MarsTicketSpec.HubStack.focusPeerOpacity : 1)
                        .rotation3DEffect(
                            .degrees(tilt),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .center,
                            perspective: 0.65
                        )
                        .padding(.horizontal, MarsTicketSpec.HubStack.horizontalInset)
                        .offset(y: y)
                        .offset(x: lift.width, y: lift.height)
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
        .onPreferenceChange(TicketStackHeightKey.self) { newValue in
            guard abs(reportedHeight - newValue) > 0.5 else { return }
            reportedHeight = newValue
        }
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
                    canvasSize: CGSize(width: 390, height: 800),
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
            .coordinateSpace(name: HubTicketCanvas.spaceName)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
    return PreviewHost()
}

struct HubCanvasSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

