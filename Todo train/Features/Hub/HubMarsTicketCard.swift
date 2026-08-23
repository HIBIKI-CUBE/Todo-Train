//
//  HubMarsTicketCard.swift
//  Todo train
//
//  Full Mars face. Deck cards only select; finger follow lives on the
//  Hub present overlay so the deck is not redrawn every drag sample.
//

import SwiftUI

struct HubMarsTicketCard: View {
    let ticket: Ticket
    var isLifted: Bool = false
    var isHeldVisually: Bool = false
    var canBoard: Bool = false
    var disabledReason: String?
    var restOffset: CGSize = .zero
    var followsFinger: Bool = true
    let onSelect: () -> Void
    var onDismissLift: () -> Void = {}
    var onHoldDragEnded: ((DragGesture.Value) -> TicketStackLayout.HoldRelease)?

    @State private var dragTranslation: CGSize = .zero

    private var content: MarsTicketContent {
        MarsTicketContent(ticket: ticket)
    }

    private var liveHold: CGSize {
        TicketStackLayout.holdOffset(rest: restOffset, translation: dragTranslation)
    }

    var body: some View {
        MarsTicketView(content: content, density: .hub)
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
            .gesture(isLifted && followsFinger ? holdDrag : nil)
            .offset(followsFinger ? liveHold : .zero)
            .shadow(
                color: .black.opacity(isHeldVisually || isLifted ? 0.28 : 0.18),
                radius: isHeldVisually || isLifted ? 16 : 10,
                y: isHeldVisually || isLifted ? 8 : 5
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(
                isLifted
                    ? (canBoard
                        ? "右に投げて発車。左または下、タップで戻す。詳細は長押しメニュー"
                        : "左または下、タップで戻す。\(disabledReason ?? "今は発車できません")。詳細は長押しメニュー")
                    : "つまんで発車または詳細"
            )
            .onChange(of: isLifted) { _, lifted in
                if !lifted {
                    dragTranslation = .zero
                }
            }
    }

    private func handleTap() {
        if isLifted {
            onDismissLift()
        } else {
            onSelect()
        }
    }

    private var holdDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    dragTranslation = value.translation
                }
            }
            .onEnded { value in
                let action = onHoldDragEnded?(value) ?? .putBack
                if action == .snap {
                    withAnimation(MarsTicketSpec.HubStack.focus) {
                        dragTranslation = .zero
                    }
                }
            }
    }
}

#Preview {
    let ticket = Ticket(title: "週次レビュー", estimatedSeconds: 1_500, sortOrder: 0)
    return HubMarsTicketCard(
        ticket: ticket,
        isLifted: true,
        canBoard: true,
        onSelect: {}
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
