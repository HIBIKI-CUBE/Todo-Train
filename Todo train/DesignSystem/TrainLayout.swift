//
//  TrainLayout.swift
//  Todo train
//
//  Scene-size adaptive layout. Rotation and iPhone Mirroring resize are
//  bounds changes — never UIDevice orientation or UIScreen.main.
//

import SwiftUI

enum TrainLayout {
    /// Ideal left pane for Hub split (service + paused).
    static let hubServicePaneIdealWidth: CGFloat = 280

    /// Historical alias for the ideal pane width.
    static let hubServicePaneWidth: CGFloat = hubServicePaneIdealWidth

    /// Service pane never claims more than this fraction of the scene.
    static let hubServicePaneMaxFraction: CGFloat = 0.38

    /// Below this, a service pane is not worth splitting.
    static let hubServicePaneMinimumWidth: CGFloat = 120

    /// Ticket column needs at least this much after the service pane.
    static let hubMinimumTicketPaneWidth: CGFloat = 220

    static func isCompactHeight(_ verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        verticalSizeClass == .compact
    }

    static func navigationBarTitleDisplayMode(
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> NavigationBarItem.TitleDisplayMode {
        isCompactHeight(verticalSizeClass) ? .inline : .large
    }

    /// Compact height is necessary but not sufficient: a narrow mirrored window stays one column.
    /// Width 0 is "not measured yet" — treat as split so landscape does not flash a portrait stack.
    static func shouldSplitHub(availableWidth: CGFloat, compactHeight: Bool) -> Bool {
        guard compactHeight else { return false }
        if availableWidth <= 1 { return true }
        return hubServicePaneWidth(for: availableWidth) > 0
    }

    /// 0 means do not split — caller must use a single column.
    static func hubServicePaneWidth(for availableWidth: CGFloat) -> CGFloat {
        if availableWidth <= 1 { return hubServicePaneIdealWidth }
        let ideal = min(hubServicePaneIdealWidth, availableWidth * hubServicePaneMaxFraction)
        let pane = min(ideal, availableWidth - hubMinimumTicketPaneWidth)
        guard pane >= hubServicePaneMinimumWidth else { return 0 }
        return pane
    }

    static func ticketFaceSize(
        containerWidth: CGFloat,
        horizontalInset: CGFloat = MarsTicketSpec.HubStack.horizontalInset
    ) -> CGSize {
        let width = max(1, containerWidth - horizontalInset * 2)
        return CGSize(width: width, height: MarsTicketSpec.height(forWidth: width))
    }

    /// Presented / overlay ticket size follows the live container, never a stale slot width.
    static func presentedCardSize(
        overlayWidth: CGFloat,
        horizontalInset: CGFloat = MarsTicketSpec.HubStack.horizontalInset
    ) -> CGSize {
        ticketFaceSize(containerWidth: overlayWidth, horizontalInset: horizontalInset)
    }

    static func slotFrames(
        reported: [UUID: CGRect],
        keeping ids: Set<UUID>
    ) -> [UUID: CGRect] {
        reported.filter { ids.contains($0.key) }
    }

    /// Deck layout math in canvas space. One stack origin, not a GeometryReader per card.
    static func slotFrames(
        deckFrame: CGRect,
        orderedIDs: [UUID],
        peekStep: CGFloat = MarsTicketSpec.HubStack.peekStep,
        horizontalInset: CGFloat = MarsTicketSpec.HubStack.horizontalInset
    ) -> [UUID: CGRect] {
        guard deckFrame.width > 0, !orderedIDs.isEmpty else { return [:] }
        let face = ticketFaceSize(containerWidth: deckFrame.width, horizontalInset: horizontalInset)
        let x = deckFrame.minX + (deckFrame.width - face.width) / 2
        var frames: [UUID: CGRect] = [:]
        frames.reserveCapacity(orderedIDs.count)
        for (index, id) in orderedIDs.enumerated() {
            frames[id] = CGRect(
                x: x,
                y: deckFrame.minY + CGFloat(index) * peekStep,
                width: face.width,
                height: face.height
            )
        }
        return frames
    }

    static func slotFramesMatch(
        _ lhs: [UUID: CGRect],
        _ rhs: [UUID: CGRect],
        tolerance: CGFloat = 0.5
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (id, left) in lhs {
            guard let right = rhs[id] else { return false }
            if abs(left.minX - right.minX) > tolerance
                || abs(left.minY - right.minY) > tolerance
                || abs(left.width - right.width) > tolerance
                || abs(left.height - right.height) > tolerance {
                return false
            }
        }
        return true
    }

    /// Scroll reports a new deck origin every frame. Writing that into Hub `@State`
    /// rebuilds the whole wallet. Live frames are only for present / issue overlays.
    static func shouldPublishSlotFrames(
        needsLiveFrames: Bool,
        reported: [UUID: CGRect],
        published: [UUID: CGRect]
    ) -> Bool {
        needsLiveFrames && !slotFramesMatch(reported, published)
    }

    /// Shrink an oversized landing frame around its center; keep Mars aspect.
    static func clampedLandingRect(_ rect: CGRect, containerSize: CGSize) -> CGRect {
        let face = ticketFaceSize(containerWidth: containerSize.width)
        let width = min(max(1, rect.width), face.width)
        let height = MarsTicketSpec.height(forWidth: width)
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Hub present: boarding forecast plate under the ticket when vertical room remains.
    static func shouldShowTimetablePlate(
        overlayHeight: CGFloat,
        ticketHeight: CGFloat,
        plateHeight: CGFloat,
        gap: CGFloat = MarsTicketSpec.HubStack.departSignGap,
        bottomMargin: CGFloat = MarsTicketSpec.HubStack.timetablePlateBottomMargin
    ) -> Bool {
        let available = overlayHeight / 2 - ticketHeight / 2 - gap - bottomMargin
        return available >= plateHeight
    }
}

extension EnvironmentValues {
    /// True when vertical space is limited (e.g. iPhone landscape, short mirrored window).
    var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }
}
