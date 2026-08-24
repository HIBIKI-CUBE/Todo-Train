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
        maxPeeks: Int = Int.max
    ) -> [UUID: CGFloat] {
        _ = maxPeeks
        guard !orderedIDs.isEmpty else { return [:] }
        var result: [UUID: CGFloat] = [:]
        for (i, id) in orderedIDs.enumerated() {
            result[id] = CGFloat(i) * peekStep
        }
        return result
    }

    /// Front (last) ticket shows its full face; peeks above are whatever sticks out.
    static func totalHeight(
        orderedCount: Int,
        faceHeight: CGFloat,
        peekStep: CGFloat = MarsTicketSpec.HubStack.peekStep,
        maxPeeks: Int = Int.max
    ) -> CGFloat {
        _ = maxPeeks
        guard orderedCount > 0 else { return 0 }
        if orderedCount == 1 { return faceHeight }
        return faceHeight + CGFloat(orderedCount - 1) * peekStep
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

    /// Rest pose while held: a little above the slot.
    static func liftOffset(
        isLifted: Bool,
        rise: CGFloat = MarsTicketSpec.HubStack.liftRise
    ) -> CGSize {
        isLifted ? CGSize(width: 0, height: -rise) : .zero
    }

    /// Finger follow from a rest pose (center present, or the old in-place rise).
    static func holdOffset(
        rest: CGSize,
        translation: CGSize,
        upwardFactor: CGFloat = 0.32,
        downwardOverflowFactor: CGFloat = 0.22,
        horizontalOverflowPast: CGFloat = 220,
        horizontalOverflowFactor: CGFloat = 0.22
    ) -> CGSize {
        var dy = translation.height
        if dy < 0 {
            dy *= upwardFactor
        }
        let slotRelativeY = rest.height + dy
        if slotRelativeY > 0 {
            dy = -rest.height + slotRelativeY * downwardOverflowFactor
        }

        var dx = translation.width
        let absX = abs(dx)
        if absX > horizontalOverflowPast {
            let overflow = absX - horizontalOverflowPast
            dx = (dx < 0 ? -1 : 1) * (horizontalOverflowPast + overflow * horizontalOverflowFactor)
        }

        return CGSize(width: rest.width + dx, height: rest.height + dy)
    }

    /// Finger follow from the held rest pose. Down is 1:1 into the slot, then rubber-bands.
    /// Left/right track 1:1 so a throw can leave the deck.
    static func holdOffset(
        restRise: CGFloat,
        translation: CGSize,
        upwardFactor: CGFloat = 0.32,
        downwardOverflowFactor: CGFloat = 0.22,
        horizontalOverflowPast: CGFloat = 220,
        horizontalOverflowFactor: CGFloat = 0.22
    ) -> CGSize {
        holdOffset(
            rest: CGSize(width: 0, height: -restRise),
            translation: translation,
            upwardFactor: upwardFactor,
            downwardOverflowFactor: downwardOverflowFactor,
            horizontalOverflowPast: horizontalOverflowPast,
            horizontalOverflowFactor: horizontalOverflowFactor
        )
    }

    /// Scale tracks how far the card still is from its slot (1 at rest lift).
    static func holdScale(
        holdY: CGFloat,
        restRise: CGFloat,
        liftedScale: CGFloat
    ) -> CGFloat {
        guard restRise > 0 else { return 1 }
        let t = min(1, max(0, -holdY / restRise))
        return 1 + (liftedScale - 1) * t
    }

    static func shouldPutBack(
        hold: CGSize,
        translation: CGSize,
        predictedEnd: CGSize
    ) -> Bool {
        let moved = hypot(translation.width, translation.height) > 12
        let nearSlot = moved && hypot(hold.width, hold.height) < 40
        let pulled = translation.height > 72
        let flicked = predictedEnd.height > 100
        return nearSlot || pulled || flicked
    }

    /// Legacy tests / callers that only know vertical rest.
    static func shouldPutBack(
        holdY: CGFloat,
        translation: CGSize,
        predictedEnd: CGSize,
        restRise: CGFloat
    ) -> Bool {
        _ = restRise
        return shouldPutBack(
            hold: CGSize(width: 0, height: holdY),
            translation: translation,
            predictedEnd: predictedEnd
        )
    }

    enum HoldRelease: Equatable {
        case board
        case putBack
        case snap
    }

    /// Resting-deck swipe: leading full-swipe boards, trailing deletes (HIG list edges).
    enum DeckSwipeRelease: Equatable {
        case board
        case delete
        case snap
    }

    /// Board only on a committed right throw. Anything else puts the ticket back.
    static func holdRelease(
        hold: CGSize,
        translation: CGSize,
        predictedEnd: CGSize,
        canBoard: Bool,
        boardDistance: CGFloat = 140
    ) -> HoldRelease {
        _ = hold
        if canBoard, isCommittedRightThrow(
            translation: translation,
            predictedEnd: predictedEnd,
            boardDistance: boardDistance
        ) {
            return .board
        }
        return .putBack
    }

    static func isCommittedRightThrow(
        translation: CGSize,
        predictedEnd: CGSize,
        boardDistance: CGFloat = 140
    ) -> Bool {
        translation.width >= boardDistance
            && translation.width > abs(translation.height)
            && predictedEnd.width >= translation.width
    }

    /// Positive = toward the leading edge (right in LTR, left in RTL).
    static func leadingWidth(
        translationWidth: CGFloat,
        leadingIsPositiveX: Bool
    ) -> CGFloat {
        leadingIsPositiveX ? translationWidth : -translationWidth
    }

    static func isCommittedLeadingThrow(
        translation: CGSize,
        predictedEnd: CGSize,
        leadingIsPositiveX: Bool,
        boardDistance: CGFloat = 140
    ) -> Bool {
        let width = leadingWidth(
            translationWidth: translation.width,
            leadingIsPositiveX: leadingIsPositiveX
        )
        let predicted = leadingWidth(
            translationWidth: predictedEnd.width,
            leadingIsPositiveX: leadingIsPositiveX
        )
        return width >= boardDistance
            && width > abs(translation.height)
            && predicted >= width
    }

    static func isCommittedTrailingThrow(
        translation: CGSize,
        predictedEnd: CGSize,
        leadingIsPositiveX: Bool,
        boardDistance: CGFloat = 140
    ) -> Bool {
        let width = leadingWidth(
            translationWidth: translation.width,
            leadingIsPositiveX: leadingIsPositiveX
        )
        let predicted = leadingWidth(
            translationWidth: predictedEnd.width,
            leadingIsPositiveX: leadingIsPositiveX
        )
        return width <= -boardDistance
            && -width > abs(translation.height)
            && predicted <= width
    }

    /// Full swipe on an unselected peek. Partial swipes snap back (tap still presents).
    static func deckSwipeRelease(
        translation: CGSize,
        predictedEnd: CGSize,
        canBoard: Bool,
        leadingIsPositiveX: Bool,
        boardDistance: CGFloat = 140
    ) -> DeckSwipeRelease {
        if canBoard, isCommittedLeadingThrow(
            translation: translation,
            predictedEnd: predictedEnd,
            leadingIsPositiveX: leadingIsPositiveX,
            boardDistance: boardDistance
        ) {
            return .board
        }
        if isCommittedTrailingThrow(
            translation: translation,
            predictedEnd: predictedEnd,
            leadingIsPositiveX: leadingIsPositiveX,
            boardDistance: boardDistance
        ) {
            return .delete
        }
        return .snap
    }

    static func holdRelease(
        holdY: CGFloat,
        translation: CGSize,
        predictedEnd: CGSize,
        restRise: CGFloat,
        canBoard: Bool,
        boardDistance: CGFloat = 140,
        boardPredicted: CGFloat = 110,
        dismissDistance: CGFloat = 64,
        dismissPredicted: CGFloat = 100
    ) -> HoldRelease {
        _ = restRise
        _ = boardPredicted
        _ = dismissDistance
        _ = dismissPredicted
        return holdRelease(
            hold: CGSize(width: 0, height: holdY),
            translation: translation,
            predictedEnd: predictedEnd,
            canBoard: canBoard,
            boardDistance: boardDistance
        )
    }
}
