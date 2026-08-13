//
//  TicketStackLayout.swift
//  Todo train
//
//  Pure layout math for the Hub Wallet-style Mars ticket stack.
//

import CoreGraphics
import Foundation

enum TicketStackLayout {
    /// Display order: front first, then peeks behind (backlog sortOrder ascending → front is first).
    /// Returns y-offsets from the top of the stack container for each index in `orderedIDs`
    /// when `frontID` is expanded at the front.
    static func offsets(
        orderedIDs: [UUID],
        frontID: UUID?,
        ticketHeight: CGFloat,
        peekStep: CGFloat = MarsTicketSpec.HubStack.peekStep(visibleCount: 1),
        maxPeeks: Int = MarsTicketSpec.HubStack.maxVisiblePeeks
    ) -> [UUID: CGFloat] {
        guard !orderedIDs.isEmpty else { return [:] }
        let front = frontID.flatMap { orderedIDs.contains($0) ? $0 : nil } ?? orderedIDs[0]
        var rest = orderedIDs.filter { $0 != front }
        if rest.count > maxPeeks - 1 {
            rest = Array(rest.prefix(maxPeeks - 1))
        }

        var result: [UUID: CGFloat] = [:]
        // Peeks sit above the front card strip (Wallet: stack grows downward from peeks into front).
        // Visual: peeks first (small y), then front at y = peeks * step.
        for (i, id) in rest.enumerated() {
            result[id] = CGFloat(i) * peekStep
        }
        result[front] = CGFloat(rest.count) * peekStep
        return result
    }

    static func totalHeight(
        orderedCount: Int,
        ticketHeight: CGFloat,
        boardBarHeight: CGFloat = MarsTicketSpec.HubStack.frontBoardBarHeight,
        peekStep: CGFloat = MarsTicketSpec.HubStack.peekStep(visibleCount: 1),
        maxPeeks: Int = MarsTicketSpec.HubStack.maxVisiblePeeks
    ) -> CGFloat {
        guard orderedCount > 0 else { return 0 }
        let visible = min(orderedCount, maxPeeks)
        let behind = max(0, visible - 1)
        return ticketHeight + boardBarHeight + CGFloat(behind) * peekStep
    }

    /// After bringing `tapped` to front, new ordered list for sort persistence (front first).
    static func orderByBringingToFront(orderedIDs: [UUID], tapped: UUID) -> [UUID] {
        guard orderedIDs.contains(tapped) else { return orderedIDs }
        return [tapped] + orderedIDs.filter { $0 != tapped }
    }
}
