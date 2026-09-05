//
//  HubMarsTicketCard.swift
//  Todo train
//
//  Full Mars face. Deck cards select on tap and full-swipe on the list edges
//  (leading = board, trailing = delete). Finger follow for a lifted ticket
//  lives on the Hub present overlay so the deck is not redrawn every sample.
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
    var allowsDeckSwipe: Bool = false
    let onSelect: () -> Void
    var onDismissLift: () -> Void = {}
    var onHoldDragEnded: ((DragGesture.Value) -> TicketStackLayout.HoldRelease)?
    var onDeckSwipeActive: (Bool) -> Void = { _ in }
    var onDeckSwipeEnded: (TicketStackLayout.DeckSwipeRelease) -> Void = { _ in }

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragTranslation: CGSize = .zero
    @State private var deckAxisLocked = false
    @State private var deckAxisCancelled = false

    private var content: MarsTicketContent {
        MarsTicketContent(ticket: ticket)
    }

    private var leadingIsPositiveX: Bool {
        layoutDirection == .leftToRight
    }

    private var liveHold: CGSize {
        TicketStackLayout.holdOffset(rest: restOffset, translation: dragTranslation)
    }

    private var leadingDrag: CGFloat {
        TicketStackLayout.leadingWidth(
            translationWidth: liveHold.width,
            leadingIsPositiveX: leadingIsPositiveX
        )
    }

    var body: some View {
        ZStack {
            if allowsDeckSwipe, !isLifted {
                deckActionBackdrop
            }
            MarsTicketView(content: content, density: .hub)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)
                .gesture(isLifted && followsFinger ? holdDrag : nil)
                .simultaneousGesture(!isLifted && allowsDeckSwipe ? deckDrag : nil)
                .offset(followsFinger || allowsDeckSwipe ? liveHold : .zero)
                .shadow(
                    color: .black.opacity(isHeldVisually || isLifted ? 0.28 : 0.18),
                    radius: isHeldVisually || isLifted ? 16 : 10,
                    y: isHeldVisually || isLifted ? 8 : 5
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(accessibilityHintText)
        .onChange(of: isLifted) { _, lifted in
            if !lifted {
                dragTranslation = .zero
                resetDeckAxis()
            }
        }
    }

    private var accessibilityHintText: String {
        if isLifted {
            return canBoard
                ? "右に投げて発車。左または下、タップで戻す。詳細は長押しメニュー"
                : "左または下、タップで戻す。\(disabledReason ?? "今は発車できません")。詳細は長押しメニュー"
        }
        if canBoard {
            return "ダブルタップでつまむ。発車と削除はアクションから。詳細は長押しメニュー"
        }
        return "ダブルタップでつまむ。削除はアクションから。\(disabledReason ?? "今は発車できません")。詳細は長押しメニュー"
    }

    @ViewBuilder
    private var deckActionBackdrop: some View {
        let progress = min(1, abs(leadingDrag) / 80)
        let towardLeading = leadingDrag > 8
        let towardTrailing = leadingDrag < -8
        RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
            .fill(backdropColor(towardLeading: towardLeading, towardTrailing: towardTrailing))
            .overlay(alignment: towardLeading ? .leading : .trailing) {
                if towardLeading || towardTrailing {
                    backdropLabel(towardLeading: towardLeading)
                        .opacity(progress)
                        .padding(.horizontal, TrainTheme.Space.md)
                }
            }
            .opacity(progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func backdropColor(towardLeading: Bool, towardTrailing: Bool) -> Color {
        if towardLeading {
            return canBoard ? TrainTheme.rail : TrainTheme.muted.opacity(0.45)
        }
        if towardTrailing {
            return Color.red
        }
        return .clear
    }

    @ViewBuilder
    private func backdropLabel(towardLeading: Bool) -> some View {
        if towardLeading {
            Label("発車", systemImage: "arrow.forward")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .symbolVariant(.fill)
        } else {
            Label("削除", systemImage: "trash")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .symbolVariant(.fill)
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

    private var deckDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if deckAxisCancelled { return }
                if !deckAxisLocked {
                    let t = value.translation
                    if abs(t.width) > abs(t.height) {
                        deckAxisLocked = true
                        onDeckSwipeActive(true)
                    } else {
                        deckAxisCancelled = true
                        return
                    }
                }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    dragTranslation = value.translation
                }
            }
            .onEnded { value in
                let wasHorizontal = deckAxisLocked
                if wasHorizontal {
                    let action = TicketStackLayout.deckSwipeRelease(
                        translation: value.translation,
                        predictedEnd: value.predictedEndTranslation,
                        canBoard: canBoard,
                        leadingIsPositiveX: leadingIsPositiveX
                    )
                    onDeckSwipeEnded(action)
                    switch action {
                    case .snap:
                        withAnimation(MarsTicketSpec.HubStack.putBack) {
                            dragTranslation = .zero
                        }
                    case .board, .delete:
                        break
                    }
                    onDeckSwipeActive(false)
                }
                resetDeckAxis()
            }
    }

    private func resetDeckAxis() {
        deckAxisLocked = false
        deckAxisCancelled = false
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
