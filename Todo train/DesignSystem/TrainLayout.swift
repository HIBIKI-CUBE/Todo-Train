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
        MarsTicketSpec.clampedLandingRect(rect, containerSize: containerSize)
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

    /// Board (the 372×782 grid) fitted inside one safe rect. Uniform scale, centered.
    /// An unmeasured side (non-finite, or 1pt or less) keeps the design length on that side.
    /// When the rect is smaller than the grid, the whole board shrinks.
    static func openingPanelPlacement(in safe: CGRect) -> OpeningPanelPlacement {
        let design = OpeningPanelTokens.Canvas.outer
        let width = safe.width.isFinite && safe.width > 1 ? safe.width : design.width
        let height = safe.height.isFinite && safe.height > 1 ? safe.height : design.height
        let scale = min(width / design.width, height / design.height)
        let size = CGSize(width: design.width * scale, height: design.height * scale)
        let origin = CGPoint(
            x: safe.minX + (width - size.width) / 2,
            y: safe.minY + (height - size.height) / 2
        )
        return OpeningPanelPlacement(scale: scale, origin: origin, size: size)
    }

    /// Scaled board size for `available`, origin at the top-left of that rect.
    static func openingPanelSize(fitting available: CGSize) -> CGSize {
        openingPanelPlacement(in: CGRect(origin: .zero, size: available)).size
    }
}

struct OpeningPanelPlacement: Equatable {
    var scale: CGFloat
    var origin: CGPoint
    var size: CGSize
}

/// Hit rectangles for the opening panel, in the grid's design space (canvas top-left).
/// Visual size stays the mock's. Hits grow to `minimum` without crossing a neighbor.
/// A row of controls closer than `minimum` keeps the gap between them: the hit covers
/// the visual and takes the free side, and does not overlap the next control.
enum OpeningPanelHitLayout {
    static let minimumScreen: CGFloat = 44

    enum ID: Hashable {
        case master
        case clockKey
        case hourMode
        case scaleToggle
        case timetableKey
        case sequence
        case ticketsKey
        case commTest
        case depart
        case todayRail
        case ticketRow(Int)
        case timetableBand(String)
        case timetableRow(String)

        var entryID: String? {
            switch self {
            case .timetableBand(let id), .timetableRow(let id):
                return id
            default:
                return nil
            }
        }
    }

    struct Target: Equatable, Identifiable {
        var id: ID
        var visual: CGRect
        var hit: CGRect
    }

    /// Fixed controls, the rail, and ticket rows. Confirmation and power are not inputs.
    static func board(minimum: CGFloat, ticketRows: Int) -> [Target] {
        let floor = max(1, minimum)
        let visuals = fixedVisuals(ticketRows: max(0, ticketRows))
        let claims = fixedClaims(minimum: floor, ticketRows: max(0, ticketRows))
        return zip(visuals, claims).map { visual, claim in
            Target(id: visual.id, visual: visual.rect, hit: claim)
        }
    }

    /// Timetable bands and labels inside `bounds` (tape space). Same geometry at every stage.
    static func timetable(
        entries: [OpeningTimetableEntry],
        range: TimetableRange,
        bounds: CGRect,
        minimum: CGFloat
    ) -> [Target] {
        guard bounds.width > 1, bounds.height > 1, !entries.isEmpty else { return [] }
        let frames = TimetableColumnLayout.rowFrames(
            entries: entries,
            range: range,
            height: bounds.height
        )
        let rowWidth = max(0, bounds.width - TimetableColumnLayout.rowOrigin)
        var visuals: [(ID, CGRect)] = []
        visuals.reserveCapacity(frames.count * 2)
        for frame in frames {
            visuals.append((
                .timetableBand(frame.id),
                CGRect(
                    x: bounds.minX + TimetableColumnLayout.barOrigin,
                    y: bounds.minY + frame.bandTop,
                    width: TimetableColumnLayout.barWidth,
                    height: frame.bandHeight
                )
            ))
            visuals.append((
                .timetableRow(frame.id),
                CGRect(
                    x: bounds.minX + TimetableColumnLayout.rowOrigin,
                    y: bounds.minY + frame.top,
                    width: rowWidth,
                    height: TimetableColumnLayout.rowHeight
                )
            ))
        }
        let expanded = expand(visuals.map(\.1), minimum: minimum, bounds: bounds)
        return zip(visuals, expanded).map { visual, hit in
            Target(id: visual.0, visual: visual.1, hit: hit)
        }
    }

    /// Grows each rect toward `minimum` on both axes. Stops at `bounds` or a neighbor.
    /// The result contains the visual whenever the visuals themselves do not overlap.
    static func expand(_ visuals: [CGRect], minimum: CGFloat, bounds: CGRect) -> [CGRect] {
        let floor = max(1, minimum)
        var rects = visuals.map { $0.standardized }
        let order = [Edge.up, Edge.left, Edge.down, Edge.right]
        var grew = true
        var pass = 0
        while grew && pass < 600 {
            grew = false
            pass += 1
            let indexes: [Int] = pass % 2 == 0
                ? Array(rects.indices.reversed())
                : Array(rects.indices)
            for index in indexes {
                for edge in order {
                    let current = rects[index]
                    let alongWidth = edge == .left || edge == .right
                    if alongWidth {
                        guard current.width + 0.5 < floor else { continue }
                    } else {
                        guard current.height + 0.5 < floor else { continue }
                    }
                    var proposed = current
                    switch edge {
                    case .left:
                        proposed.origin.x -= 1
                        proposed.size.width += 1
                    case .right:
                        proposed.size.width += 1
                    case .up:
                        proposed.origin.y -= 1
                        proposed.size.height += 1
                    case .down:
                        proposed.size.height += 1
                    }
                    guard encloses(bounds, proposed) else { continue }
                    guard encloses(proposed, visuals[index]) else { continue }
                    if rects.enumerated().contains(where: { offset, other in
                        offset != index && overlaps(proposed, other)
                    }) {
                        continue
                    }
                    rects[index] = proposed
                    grew = true
                }
            }
        }
        return rects
    }

    private enum Edge {
        case up, left, down, right
    }

    private static func encloses(_ outer: CGRect, _ inner: CGRect) -> Bool {
        inner.minX >= outer.minX - 0.05
            && inner.minY >= outer.minY - 0.05
            && inner.maxX <= outer.maxX + 0.05
            && inner.maxY <= outer.maxY + 0.05
    }

    private static func overlaps(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let rect = lhs.intersection(rhs)
        return rect.width > 0.5 && rect.height > 0.5
    }

    private struct Placed {
        var id: ID
        var rect: CGRect
    }

    private static func fixedVisuals(ticketRows: Int) -> [Placed] {
        var placed: [Placed] = [
            Placed(id: .master, rect: OpeningPanelTokens.Module.master.frame()),
            Placed(id: .clockKey, rect: clockKeyVisual),
            Placed(id: .hourMode, rect: hourModeVisual),
            Placed(id: .scaleToggle, rect: scaleToggleVisual),
            Placed(id: .timetableKey, rect: timetableKeyVisual),
            Placed(id: .sequence, rect: sequenceVisual),
            Placed(id: .ticketsKey, rect: ticketsKeyVisual),
            Placed(id: .commTest, rect: commTestVisual),
            Placed(id: .depart, rect: departVisual),
            Placed(id: .todayRail, rect: railVisual)
        ]
        for index in 0..<ticketRows {
            placed.append(Placed(id: .ticketRow(index), rect: ticketRowVisual(index)))
        }
        return placed
    }

    private static func fixedClaims(minimum: CGFloat, ticketRows: Int) -> [CGRect] {
        let clock = clockColumnClaims(minimum: minimum)
        var claims: [CGRect] = [
            OpeningPanelTokens.Module.master.frame(),
            clock.key,
            clock.hour,
            scaleToggleClaim(minimum: minimum),
            timetableKeyClaim(minimum: minimum),
            sequenceClaim(minimum: minimum),
            ticketsKeyClaim(minimum: minimum),
            commTestClaim(minimum: minimum),
            departVisual,
            railClaim(minimum: minimum)
        ]
        claims.append(contentsOf: ticketRowClaims(count: ticketRows, minimum: minimum))
        return claims
    }

    private static var clockKeyVisual: CGRect {
        let module = OpeningPanelTokens.Module.clockKey.frame()
        return CGRect(x: module.midX - 28, y: module.minY + 28, width: 56, height: 40)
    }

    private static var hourModeVisual: CGRect {
        let module = OpeningPanelTokens.Module.clockKey.frame()
        return CGRect(x: module.minX + 8, y: module.maxY - 28, width: 70, height: 22)
    }

    private static func clockColumnClaims(minimum: CGFloat) -> (key: CGRect, hour: CGRect) {
        let module = OpeningPanelTokens.Module.clockKey.frame()
        let keyVisual = clockKeyVisual
        let hourVisual = hourModeVisual
        let split = keyVisual.maxY + (hourVisual.minY - keyVisual.maxY) / 2
        var hour = CGRect(
            x: module.minX,
            y: split,
            width: module.width,
            height: max(minimum, hourVisual.maxY - split)
        )
        var key = CGRect(
            x: module.minX,
            y: module.minY,
            width: module.width,
            height: split - module.minY
        )
        if key.height < minimum {
            let extra = minimum - key.height
            key.origin.y -= extra
            key.size.height = minimum
        }
        if hour.minY < key.maxY {
            hour.origin.y = key.maxY
        }
        return (key, hour)
    }

    private static var scaleToggleVisual: CGRect {
        let module = OpeningPanelTokens.Module.timetable.frame()
        return CGRect(x: module.minX + 70, y: module.minY + 6, width: 48, height: 22)
    }

    private static func scaleToggleClaim(minimum: CGFloat) -> CGRect {
        let visual = scaleToggleVisual
        let height = max(minimum, visual.height)
        return CGRect(
            x: visual.minX - 4,
            y: visual.minY,
            width: max(minimum, visual.width + 8),
            height: height
        )
    }

    private static var timetableKeyVisual: CGRect {
        let module = OpeningPanelTokens.Module.timetable.frame()
        return CGRect(x: module.maxX - 6 - 52, y: module.maxY - 5 - 30, width: 52, height: 30)
    }

    private static func timetableKeyClaim(minimum: CGFloat) -> CGRect {
        let visual = timetableKeyVisual
        let height = max(minimum, visual.height)
        let width = max(minimum, visual.width)
        return CGRect(
            x: visual.maxX - width,
            y: visual.maxY - height,
            width: width,
            height: height
        )
    }

    private static var ticketsHeader: (module: CGRect, seq: CGRect, key: CGRect) {
        let module = OpeningPanelTokens.Module.tickets.frame()
        let pad: CGFloat = 6
        let headerY = module.minY + pad
        let key = CGRect(x: module.maxX - pad - 64, y: headerY, width: 64, height: 30)
        let seq = CGRect(x: key.minX - 8 - 36, y: headerY + 5, width: 36, height: 20)
        return (module, seq, key)
    }

    private static var sequenceVisual: CGRect { ticketsHeader.seq }
    private static var ticketsKeyVisual: CGRect { ticketsHeader.key }

    private static func sequenceClaim(minimum: CGFloat) -> CGRect {
        let visual = sequenceVisual
        let width = max(minimum, visual.width)
        let height = max(minimum, visual.height)
        return CGRect(x: visual.midX - width / 2, y: visual.midY - height / 2, width: width, height: height)
    }

    private static func ticketsKeyClaim(minimum: CGFloat) -> CGRect {
        let visual = ticketsKeyVisual
        let width = max(minimum, visual.width)
        let height = max(minimum, visual.height)
        return CGRect(x: visual.midX - width / 2, y: visual.midY - height / 2, width: width, height: height)
    }

    private static var ticketContent: (window: CGRect, rail: CGRect, rowOriginY: CGFloat) {
        let module = OpeningPanelTokens.Module.tickets.frame()
        let pad: CGFloat = 6
        let header: CGFloat = 30
        let spacing: CGFloat = 5
        let blockY = module.minY + pad + header + spacing
        let blockH = module.height - pad - pad - header - spacing
        let innerX = module.minX + pad
        let slots: CGFloat = 34
        let mark: CGFloat = 8
        let gap: CGFloat = 4
        let railW: CGFloat = 16
        let railX = innerX + slots + gap + mark + gap
        let windowX = railX + railW + gap
        let windowW = module.maxX - pad - windowX
        return (
            CGRect(x: windowX, y: blockY, width: windowW, height: blockH),
            CGRect(x: railX, y: blockY, width: railW, height: blockH),
            blockY + OpeningPanelTicketMetrics.contentTop
        )
    }

    private static var railVisual: CGRect { ticketContent.rail }

    private static func railClaim(minimum: CGFloat) -> CGRect {
        let visual = railVisual
        let width = max(minimum, visual.width)
        return CGRect(x: visual.maxX - width, y: visual.minY, width: width, height: max(minimum, visual.height))
    }

    private static func ticketRowVisual(_ index: Int) -> CGRect {
        let content = ticketContent
        return CGRect(
            x: content.window.minX,
            y: content.rowOriginY + CGFloat(index) * OpeningPanelTicketMetrics.rowHeight,
            width: content.window.width,
            height: OpeningPanelTicketMetrics.rowHeight
        )
    }

    /// Rows stay on the 21pt pitch. Width already clears 44. Height grows only into
    /// space the neighboring row does not occupy, so the middles stay on the pitch.
    private static func ticketRowClaims(count: Int, minimum: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let visuals = (0..<count).map(ticketRowVisual)
        let content = ticketContent
        // SEQ と TKT の当たりは最初の行の上端で終わる。行はそこから下の窓の中だけで広げる。
        let bounds = CGRect(
            x: content.window.minX,
            y: content.rowOriginY,
            width: content.window.width,
            height: max(0, content.window.maxY - content.rowOriginY)
        )
        return expand(visuals, minimum: minimum, bounds: bounds)
    }

    private static var commTestVisual: CGRect {
        let module = OpeningPanelTokens.Module.comm.frame()
        return CGRect(x: module.minX + 36, y: module.minY + 2, width: 16, height: 16)
    }

    private static func commTestClaim(minimum: CGFloat) -> CGRect {
        let visual = commTestVisual
        let side = minimum
        var rect = CGRect(x: visual.midX - side / 2, y: visual.midY - side / 2, width: side, height: side)
        let rail = railClaim(minimum: minimum)
        if overlaps(rect, rail) {
            rect.origin.y = rail.maxY
        }
        if rect.minY > visual.minY {
            rect.origin.y = visual.minY
            rect.size.height = max(side, visual.maxY - rect.minY)
        }
        return rect
    }

    private static var departVisual: CGRect {
        let module = OpeningPanelTokens.Module.depart.frame()
        let x = module.minX + 8 + OpeningPanelTokens.Chrome.departReadoutWidth + OpeningPanelTokens.Chrome.departGap
        let y = module.minY + 5
        return CGRect(x: x, y: y, width: OpeningPanelTokens.Chrome.departBar.width, height: OpeningPanelTokens.Chrome.departBar.height)
    }
}

extension EnvironmentValues {
    /// True when vertical space is limited (e.g. iPhone landscape, short mirrored window).
    var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }
}
