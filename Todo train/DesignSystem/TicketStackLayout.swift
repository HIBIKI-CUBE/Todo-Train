//
//  TicketStackLayout.swift
//  Todo train
//
//  Pure layout math for the Hub Wallet-style peek deck.
//  Full Mars faces are stacked; lower cards cover upper ones (front = last = fully visible).
//

import CoreGraphics
import Foundation

enum TicketStackLayout {
    /// sortOrder ascending → top (back) to bottom (front).
    static func offsets(
        orderedIDs: [UUID],
        peekStep: CGFloat = MarsTicketSpec.HubStack.peekStep,
        maxPeeks: Int = MarsTicketSpec.HubStack.maxVisiblePeeks
    ) -> [UUID: CGFloat] {
        guard !orderedIDs.isEmpty else { return [:] }
        let visible = Array(orderedIDs.prefix(maxPeeks))
        var result: [UUID: CGFloat] = [:]
        for (i, id) in visible.enumerated() {
            result[id] = CGFloat(i) * peekStep
        }
        return result
    }

    /// Front (last) ticket shows its full face; peeks above are whatever sticks out.
    static func totalHeight(
        orderedCount: Int,
        faceHeight: CGFloat,
        peekStep: CGFloat = MarsTicketSpec.HubStack.peekStep,
        maxPeeks: Int = MarsTicketSpec.HubStack.maxVisiblePeeks
    ) -> CGFloat {
        guard orderedCount > 0 else { return 0 }
        let visible = min(orderedCount, maxPeeks)
        if visible == 1 { return faceHeight }
        return faceHeight + CGFloat(visible - 1) * peekStep
    }

    /// Index 0 = back (top), last = front (bottom). Front tilts least.
    static func tiltDegrees(
        index: Int,
        count: Int,
        near: Double = MarsTicketSpec.HubStack.tiltNearDegrees,
        far: Double = MarsTicketSpec.HubStack.tiltFarDegrees
    ) -> Double {
        guard count > 1 else { return near }
        let depth = Double(count - 1 - index) / Double(count - 1)
        return near + (far - near) * depth
    }

    /// Slot center of a stacked face, in the same space as `stackFrame`.
    static func slotCenter(
        stackFrame: CGRect,
        horizontalInset: CGFloat,
        faceWidth: CGFloat,
        faceHeight: CGFloat,
        slotTopY: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: stackFrame.minX + horizontalInset + faceWidth / 2,
            y: stackFrame.minY + slotTopY + faceHeight / 2
        )
    }

    /// Keep the ticket in its column (portrait = screen center, landscape = right pane).
    /// Vertical target is the canvas midpoint above the cabin console.
    static func liftDestination(
        stackFrame: CGRect,
        canvasSize: CGSize,
        consoleReserve: CGFloat = MarsTicketSpec.HubStack.focusConsoleLayoutReserve
    ) -> CGPoint {
        let y = max(consoleReserve / 2, (canvasSize.height - consoleReserve) / 2)
        return CGPoint(x: stackFrame.midX, y: y)
    }

    static func liftOffset(from slotCenter: CGPoint, to destination: CGPoint) -> CGSize {
        CGSize(width: destination.x - slotCenter.x, height: destination.y - slotCenter.y)
    }
}
