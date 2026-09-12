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
}

public struct OverlaySize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
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

/// Snap-to-corner and left/right tuck for the Mac ride PiP.
public enum RideOverlayGeometry {
    public static let cardSize = OverlaySize(width: 320, height: 120)
    public static let tuckedSize = OverlaySize(width: 36, height: 148)
    public static let screenInset: Double = 12
    public static let tuckThreshold: Double = 48

    public static func frame(
        for state: OverlayLayoutState,
        screen: OverlayRect,
        cardSize: OverlaySize = cardSize,
        tuckedSize: OverlaySize = tuckedSize,
        inset: Double = screenInset
    ) -> OverlayRect {
        let size = state.isTucked ? tuckedSize : cardSize
        let parked = parkedFrame(corner: state.corner, screen: screen, size: size, inset: inset)
        guard state.isTucked else { return parked }
        let x: Double
        switch state.edge {
        case .leading: x = screen.minX
        case .trailing: x = screen.maxX - size.width
        }
        return OverlayRect(x: x, y: parked.y, width: size.width, height: size.height)
    }

    public static func layout(
        afterDrag frame: OverlayRect,
        screen: OverlayRect,
        tuckThreshold: Double = tuckThreshold
    ) -> OverlayLayoutState {
        let offTrailing = frame.maxX - screen.maxX
        let offLeading = screen.minX - frame.minX
        let top = frame.midY >= screen.midY
        if offTrailing >= tuckThreshold, offTrailing >= offLeading {
            return OverlayLayoutState(
                corner: top ? .topTrailing : .bottomTrailing,
                isTucked: true
            )
        }
        if offLeading >= tuckThreshold {
            return OverlayLayoutState(
                corner: top ? .topLeading : .bottomLeading,
                isTucked: true
            )
        }
        return OverlayLayoutState(corner: nearestCorner(of: frame, screen: screen), isTucked: false)
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
        screen: OverlayRect,
        size: OverlaySize,
        inset: Double
    ) -> OverlayRect {
        let maxX = max(screen.minX, screen.maxX - size.width - inset)
        let maxY = max(screen.minY, screen.maxY - size.height - inset)
        let minX = screen.minX + inset
        let minY = screen.minY + inset
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
}
