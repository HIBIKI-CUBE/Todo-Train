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
    static func shouldSplitHub(availableWidth: CGFloat, compactHeight: Bool) -> Bool {
        compactHeight && hubServicePaneWidth(for: availableWidth) > 0
    }

    /// 0 means do not split — caller must use a single column.
    static func hubServicePaneWidth(for availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return 0 }
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

    /// ScrollView will report a child's *content* width, which can be a leftover landscape face.
    /// Never let that outgrow the current column proposal.
    static func resolvedTicketContainerWidth(measured: CGFloat, proposed: CGFloat) -> CGFloat {
        let measuredWidth = measured > 1 ? measured : 0
        let proposedWidth = proposed > 1 ? proposed : 0
        if measuredWidth > 1, proposedWidth > 1 {
            return min(measuredWidth, proposedWidth)
        }
        return max(measuredWidth, proposedWidth)
    }

    static func slotFrames(
        reported: [UUID: CGRect],
        keeping ids: Set<UUID>
    ) -> [UUID: CGRect] {
        reported.filter { ids.contains($0.key) }
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
}

extension EnvironmentValues {
    /// True when vertical space is limited (e.g. iPhone landscape, short mirrored window).
    var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }
}
