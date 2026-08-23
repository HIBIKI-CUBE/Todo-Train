//
//  TicketDeckLayout.swift
//  Todo train
//
//  Wallet peek deck sized from this layout pass's proposal width.
//  Never caches measured width — rotation is a bounds change, not a stored size.
//

import SwiftUI

struct TicketDeckLayout: Layout {
    var peekStep: CGFloat = MarsTicketSpec.HubStack.peekStep
    var horizontalInset: CGFloat = MarsTicketSpec.HubStack.horizontalInset

    /// Pure size from the column proposal. Old widths are not an input.
    static func deckSize(
        proposalWidth: CGFloat,
        orderedCount: Int,
        peekStep: CGFloat = MarsTicketSpec.HubStack.peekStep,
        horizontalInset: CGFloat = MarsTicketSpec.HubStack.horizontalInset
    ) -> CGSize {
        guard proposalWidth > 0, orderedCount > 0 else { return .zero }
        let face = TrainLayout.ticketFaceSize(
            containerWidth: proposalWidth,
            horizontalInset: horizontalInset
        )
        let height = TicketStackLayout.totalHeight(
            orderedCount: orderedCount,
            faceHeight: face.height,
            peekStep: peekStep
        )
        return CGSize(width: proposalWidth, height: height)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        Self.deckSize(
            proposalWidth: proposal.width ?? 0,
            orderedCount: subviews.count,
            peekStep: peekStep,
            horizontalInset: horizontalInset
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let face = TrainLayout.ticketFaceSize(
            containerWidth: bounds.width,
            horizontalInset: horizontalInset
        )
        let x = bounds.minX + (bounds.width - face.width) / 2
        for (index, subview) in subviews.enumerated() {
            let y = bounds.minY + CGFloat(index) * peekStep
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: face.width, height: face.height)
            )
        }
    }
}
