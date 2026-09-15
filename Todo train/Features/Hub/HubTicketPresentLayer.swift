//
//  HubTicketPresentLayer.swift
//  Todo train
//

import SwiftUI
import SwiftData

/// Cover card cloned onto the present overlay so a returning ticket tucks under Wallet peeks.
struct HubPresentCover: Identifiable {
    let ticket: Ticket
    let tilt: Double
    let slotLocal: CGRect
    var id: UUID { ticket.id }
}

/// Centered ticket + LED + timetable plate. Tilt/shadow start as the deck card so the hero does not pop.
struct HubTicketPresentLayer: View {
    let ticket: Ticket
    let size: CGSize
    let overlaySize: CGSize
    let slotLocal: CGRect
    let sourceTilt: Double
    var isPuttingBack: Bool
    var covers: [HubPresentCover]
    let canBoard: Bool
    let disabledReason: String?
    var zoomNamespace: Namespace.ID
    let onDismiss: () -> Void
    var onHoldDragEnded: (DragGesture.Value) -> TicketStackLayout.HoldRelease
    let onOpenDetail: () -> Void
    let onBoard: () -> Void
    let onDelete: () -> Void

    @State private var settled = false
    @State private var pose: CGSize?

    private var looksSettled: Bool {
        settled && !isPuttingBack
    }

    /// Peek covers stay in the overlay while the hero is in the stack's z-order.
    /// Hidden once seated so they do not clip the centered ticket. Instant; no fade.
    private var coverOpacity: Double {
        if looksSettled { return 0 }
        if isPuttingBack { return 1 }
        return MarsTicketSpec.HubStack.focusPeerOpacity
    }

    private var restCenter: CGPoint {
        CGPoint(x: overlaySize.width / 2, y: overlaySize.height / 2)
    }

    private var slotPose: CGSize {
        CGSize(
            width: slotLocal.midX - restCenter.x,
            height: slotLocal.midY - restCenter.y
        )
    }

    /// One vector for select, drag, and put-back. Nil before launch = still in the slot.
    private var displayedPose: CGSize {
        if isPuttingBack { return slotPose }
        return pose ?? slotPose
    }

    private var signHeight: CGFloat {
        size.height * MarsTicketSpec.HubStack.departSignHeightRatio
    }

    private var plateHeight: CGFloat {
        MarsTicketSpec.HubStack.timetablePlateHeight(ticketHeight: size.height)
    }

    private var showsTimetablePlate: Bool {
        TrainLayout.shouldShowTimetablePlate(
            overlayHeight: overlaySize.height,
            ticketHeight: size.height,
            plateHeight: plateHeight
        )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(looksSettled ? MarsTicketSpec.HubStack.focusDimOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .allowsHitTesting(!isPuttingBack)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("選択をやめる")

            flyingTicket

            ForEach(covers) { cover in
                coverClone(cover)
            }

            HubDepartLEDSign(
                canBoard: canBoard,
                ticketWidth: size.width,
                ticketHeight: size.height
            )
            .offset(
                y: -(size.height / 2 + MarsTicketSpec.HubStack.departSignGap + signHeight / 2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .opacity(looksSettled ? 1 : 0)
            .allowsHitTesting(false)

            if showsTimetablePlate {
                HubTimetablePlate(
                    ticket: ticket,
                    ticketWidth: size.width,
                    plateHeight: plateHeight,
                    playReveal: looksSettled
                )
                .id(ticket.id)
                .offset(
                    y: size.height / 2 + MarsTicketSpec.HubStack.departSignGap + plateHeight / 2
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(looksSettled ? 1 : 0)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            var parked = Transaction()
            parked.animation = nil
            withTransaction(parked) {
                pose = slotPose
            }
            withAnimation(MarsTicketSpec.HubStack.focus) {
                pose = .zero
                settled = true
            }
        }
        .onChange(of: overlaySize) { _, _ in
            if looksSettled {
                pose = .zero
            }
        }
    }

    private var flyingTicket: some View {
        HubMarsTicketCard(
            ticket: ticket,
            isLifted: looksSettled,
            isHeldVisually: looksSettled,
            canBoard: canBoard,
            disabledReason: disabledReason,
            restOffset: .zero,
            followsFinger: false,
            onSelect: {},
            onDismissLift: onDismiss,
            onHoldDragEnded: onHoldDragEnded
        )
        .frame(width: size.width, height: size.height)
        .rotation3DEffect(
            .degrees(looksSettled ? 0 : sourceTilt),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.65
        )
        .matchedTransitionSource(id: ticket.id, in: zoomNamespace)
        .allowsHitTesting(looksSettled)
        .contextMenu {
            Button("詳細", action: onOpenDetail)
            if canBoard {
                Button("発車", action: onBoard)
            }
            Button("削除", role: .destructive, action: onDelete)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(x: displayedPose.width, y: displayedPose.height)
        .gesture(looksSettled ? holdDrag : nil)
    }

    @ViewBuilder
    private func coverClone(_ cover: HubPresentCover) -> some View {
        let coverWidth = size.width
        let coverHeight = size.height
        HubMarsTicketCard(
            ticket: cover.ticket,
            isLifted: false,
            isHeldVisually: false,
            canBoard: canBoard,
            disabledReason: disabledReason,
            restOffset: .zero,
            followsFinger: false,
            onSelect: {},
            onDismissLift: {}
        )
        .frame(width: coverWidth, height: coverHeight)
        .rotation3DEffect(
            .degrees(cover.tilt),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.65
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(
            x: cover.slotLocal.midX - restCenter.x,
            y: cover.slotLocal.midY - restCenter.y
        )
        .opacity(coverOpacity)
        .transaction { $0.animation = nil }
    }

    private var holdDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    pose = TicketStackLayout.holdOffset(
                        rest: .zero,
                        translation: value.translation
                    )
                }
            }
            .onEnded { value in
                let action = onHoldDragEnded(value)
                if action == .board {
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        pose = TicketStackLayout.holdOffset(
                            rest: .zero,
                            translation: value.translation
                        )
                    }
                }
            }
    }
}
