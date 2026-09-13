import Foundation

/// Axis-aligned rect in AppKit coordinates (origin bottom-left). Avoids CGRect on Linux.
public struct OverlayRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(x: Double, y: Double) -> Bool {
        x >= minX && x < maxX && y >= minY && y < maxY
    }

    public func intersectionArea(with other: OverlayRect) -> Double {
        let w = min(maxX, other.maxX) - max(minX, other.minX)
        let h = min(maxY, other.maxY) - max(minY, other.minY)
        guard w > 0, h > 0 else { return 0 }
        return w * h
    }

    public func distanceSquared(toX px: Double, y py: Double) -> Double {
        let dx = max(0, max(minX - px, px - maxX))
        let dy = max(0, max(minY - py, py - maxY))
        return dx * dx + dy * dy
    }
}

public struct OverlaySize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// One display: `display` is the hardware frame, `visible` excludes menu bar and Dock.
public struct OverlayScreen: Equatable, Sendable {
    public var display: OverlayRect
    public var visible: OverlayRect

    public init(display: OverlayRect, visible: OverlayRect) {
        self.display = display
        self.visible = visible
    }

    public init(_ rect: OverlayRect) {
        self.init(display: rect, visible: rect)
    }
}

public enum OverlayCorner: String, Equatable, Sendable, Codable, CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

public enum OverlayEdge: String, Equatable, Sendable, Codable {
    case leading
    case trailing
}

public struct OverlayLayoutState: Equatable, Sendable, Codable {
    public var corner: OverlayCorner
    public var isTucked: Bool

    public init(corner: OverlayCorner, isTucked: Bool) {
        self.corner = corner
        self.isTucked = isTucked
    }

    public static let `default` = OverlayLayoutState(corner: .bottomTrailing, isTucked: false)

    public var edge: OverlayEdge {
        switch corner {
        case .topLeading, .bottomLeading: return .leading
        case .topTrailing, .bottomTrailing: return .trailing
        }
    }
}

public struct OverlayPlacement: Equatable, Sendable {
    public var state: OverlayLayoutState
    public var screenIndex: Int

    public init(state: OverlayLayoutState, screenIndex: Int) {
        self.state = state
        self.screenIndex = screenIndex
    }
}

/// Snap-to-corner and left/right off-screen slide for the Mac ride PiP.
/// The card size never changes. Tucking translates the same window past the display edge.
public enum RideOverlayGeometry {
    public static let cardSize = OverlaySize(width: 320, height: 128)
    public static let screenInset: Double = 12
    public static let peekReveal: Double = 36
    public static let tuckThreshold: Double = 120
    public static let cornerRadius: Double = 16
    public static let neighborProbe: Double = 8
    /// Visible sliver so a just-started ride still shows elapsed paint.
    public static let minimumFill: Double = 4

    /// Elapsed paint along one axis. Progress 0 is empty; otherwise at least `minimum`.
    public static func fillLength(
        progress: Double,
        total: Double,
        minimum: Double = minimumFill
    ) -> Double {
        let clamped = min(1, max(0, progress))
        guard clamped > 0, total > 0 else { return 0 }
        return min(total, max(total * clamped, minimum))
    }

    public static func frame(
        for state: OverlayLayoutState,
        screen: OverlayScreen,
        cardSize: OverlaySize = cardSize,
        inset: Double = screenInset,
        peekReveal: Double = peekReveal
    ) -> OverlayRect {
        let parked = parkedFrame(corner: state.corner, visible: screen.visible, size: cardSize, inset: inset)
        guard state.isTucked else { return parked }
        let x: Double
        switch state.edge {
        case .leading:
            x = screen.display.minX + peekReveal - cardSize.width
        case .trailing:
            x = screen.display.maxX - peekReveal
        }
        return OverlayRect(x: x, y: parked.y, width: cardSize.width, height: cardSize.height)
    }

    public static func frame(
        for state: OverlayLayoutState,
        screen: OverlayRect,
        cardSize: OverlaySize = cardSize,
        inset: Double = screenInset,
        peekReveal: Double = peekReveal
    ) -> OverlayRect {
        frame(
            for: state,
            screen: OverlayScreen(screen),
            cardSize: cardSize,
            inset: inset,
            peekReveal: peekReveal
        )
    }

    public static func layout(
        afterDrag frame: OverlayRect,
        screens: [OverlayScreen],
        tuckThreshold: Double = tuckThreshold
    ) -> OverlayPlacement {
        guard !screens.isEmpty else {
            return OverlayPlacement(state: .default, screenIndex: 0)
        }
        let index = pickScreen(for: frame, screens: screens)
        let screen = screens[index]
        let displays = screens.map(\.display)
        let offTrailing = frame.maxX - screen.display.maxX
        let offLeading = screen.display.minX - frame.minX
        let top = frame.midY >= screen.visible.midY
        if offTrailing >= tuckThreshold,
           offTrailing >= offLeading,
           !hasNeighbor(.trailing, of: screen.display, among: displays) {
            return OverlayPlacement(
                state: OverlayLayoutState(
                    corner: top ? .topTrailing : .bottomTrailing,
                    isTucked: true
                ),
                screenIndex: index
            )
        }
        if offLeading >= tuckThreshold,
           !hasNeighbor(.leading, of: screen.display, among: displays) {
            return OverlayPlacement(
                state: OverlayLayoutState(
                    corner: top ? .topLeading : .bottomLeading,
                    isTucked: true
                ),
                screenIndex: index
            )
        }
        return OverlayPlacement(
            state: OverlayLayoutState(
                corner: nearestCorner(of: frame, screen: screen.visible),
                isTucked: false
            ),
            screenIndex: index
        )
    }

    public static func layout(
        afterDrag frame: OverlayRect,
        screen: OverlayRect,
        tuckThreshold: Double = tuckThreshold
    ) -> OverlayLayoutState {
        layout(
            afterDrag: frame,
            screens: [OverlayScreen(screen)],
            tuckThreshold: tuckThreshold
        ).state
    }

    public static func nearestCorner(of frame: OverlayRect, screen: OverlayRect) -> OverlayCorner {
        let leading = frame.midX < screen.midX
        let top = frame.midY >= screen.midY
        switch (leading, top) {
        case (true, true): return .topLeading
        case (false, true): return .topTrailing
        case (true, false): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    public static func parkedFrame(
        corner: OverlayCorner,
        visible: OverlayRect,
        size: OverlaySize,
        inset: Double
    ) -> OverlayRect {
        let maxX = max(visible.minX, visible.maxX - size.width - inset)
        let maxY = max(visible.minY, visible.maxY - size.height - inset)
        let minX = visible.minX + inset
        let minY = visible.minY + inset
        let x: Double
        let y: Double
        switch corner {
        case .topLeading:
            x = minX
            y = maxY
        case .topTrailing:
            x = maxX
            y = maxY
        case .bottomLeading:
            x = minX
            y = minY
        case .bottomTrailing:
            x = maxX
            y = minY
        }
        return OverlayRect(x: x, y: y, width: size.width, height: size.height)
    }

    public static func parkedFrame(
        corner: OverlayCorner,
        screen: OverlayRect,
        size: OverlaySize,
        inset: Double
    ) -> OverlayRect {
        parkedFrame(corner: corner, visible: screen, size: size, inset: inset)
    }

    public static func pickScreen(for frame: OverlayRect, screens: [OverlayScreen]) -> Int {
        if let index = screens.firstIndex(where: { $0.display.contains(x: frame.midX, y: frame.midY) }) {
            return index
        }
        var bestIndex = 0
        var bestArea = -1.0
        for (index, screen) in screens.enumerated() {
            let area = frame.intersectionArea(with: screen.display)
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        if bestArea > 0 { return bestIndex }
        var nearestIndex = 0
        var nearest = Double.greatestFiniteMagnitude
        for (index, screen) in screens.enumerated() {
            let distance = screen.display.distanceSquared(toX: frame.midX, y: frame.midY)
            if distance < nearest {
                nearest = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }

    public static func hasNeighbor(
        _ edge: OverlayEdge,
        of display: OverlayRect,
        among displays: [OverlayRect],
        gap: Double = neighborProbe
    ) -> Bool {
        let probe: OverlayRect
        switch edge {
        case .trailing:
            probe = OverlayRect(
                x: display.maxX,
                y: display.minY,
                width: gap,
                height: display.height
            )
        case .leading:
            probe = OverlayRect(
                x: display.minX - gap,
                y: display.minY,
                width: gap,
                height: display.height
            )
        }
        return displays.contains { other in
            other != display && probe.intersectionArea(with: other) > 0
        }
    }
}
