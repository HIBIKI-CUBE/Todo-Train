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

/// Points per second, in AppKit coordinates (x right, y up).
public struct OverlayVelocity: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var speed: Double { hypot(x, y) }

    public static let zero = OverlayVelocity(x: 0, y: 0)
}

/// One drag sample. `time` is seconds on the same clock as the other samples.
public struct OverlayDragSample: Equatable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double

    public init(time: Double, x: Double, y: Double) {
        self.time = time
        self.x = x
        self.y = y
    }
}

/// Ease-out glide. `initialSlope` is dy/dx of normalized progress at the start.
/// Slope 2 is a quadratic ease-out: it leaves at twice the average speed and arrives at rest,
/// without passing the corner.
public struct OverlayGlide: Equatable, Sendable {
    public var duration: Double
    public var initialSlope: Double

    public init(duration: Double, initialSlope: Double) {
        self.duration = duration
        self.initialSlope = initialSlope
    }

    public var x1: Double { 1.0 / 3.0 }
    public var y1: Double { initialSlope / 3.0 }
    public var x2: Double { 2.0 / 3.0 }
    public var y2: Double { 1 }

    public func progress(at time: Double) -> Double {
        let t = min(1, max(0, time))
        let m = initialSlope
        return ((m - 2) * t * t * t) + ((3 - 2 * m) * t * t) + (m * t)
    }

    /// Speed along the straight path at the first instant, in points per second.
    public func initialSpeed(distance: Double) -> Double {
        guard duration > 0 else { return 0 }
        return distance * initialSlope / duration
    }
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
    /// A release at or above this speed (points per second) is a flick.
    public static let flickThreshold: Double = 150
    /// Lookahead used to choose the display a flick is heading toward.
    public static let flickProjection: Double = 0.3
    /// Release speed is the drag over this many seconds. Inside the 80–100ms band.
    public static let flickVelocityWindow: Double = 0.09
    /// An axis slower than this keeps the side of the release position.
    public static let flickAxisDeadzone: Double = 40
    public static let glideMinimumDuration: Double = 0.18
    public static let glideMaximumDuration: Double = 0.7
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

    /// Occupancy band on one axis. The span stays inside `length`, including when a minimum width is applied.
    public static func containedSpan(
        start: Double,
        end: Double,
        length: Double,
        minimum: Double = 2
    ) -> (origin: Double, length: Double)? {
        guard length > 0, end > start, minimum > 0 else { return nil }
        let leading = min(max(length * start, 0), length)
        let trailing = min(max(length * end, leading), length)
        let span = min(length, max(trailing - leading, min(minimum, length)))
        let origin = min(leading, length - span)
        guard span > 0 else { return nil }
        return (origin, span)
    }

    /// Occupancy tick on one axis. Thickness is clamped so the mark cannot leave `length`.
    public static func containedTick(
        position: Double,
        length: Double,
        thickness: Double
    ) -> (origin: Double, length: Double)? {
        guard length > 0, thickness > 0 else { return nil }
        let tick = min(thickness, length)
        let origin = min(max(length * position - tick / 2, 0), length - tick)
        return (origin, tick)
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

    /// Flick-aware snap. Below `flickThreshold`, identical to `layout(afterDrag:screens:)`.
    /// At or above it, the corner follows the signs of `velocity` and the card is never tucked.
    /// The display is the one under `release + velocity * flickProjection`.
    /// Tuck itself still looks only at `frame`, and only when the release is not a flick.
    public static func layout(
        afterDrag frame: OverlayRect,
        velocity: OverlayVelocity,
        screens: [OverlayScreen],
        tuckThreshold: Double = tuckThreshold
    ) -> OverlayPlacement {
        let placed = layout(afterDrag: frame, screens: screens, tuckThreshold: tuckThreshold)
        guard velocity.speed >= flickThreshold, !screens.isEmpty else { return placed }
        let projected = OverlayRect(
            x: frame.x + velocity.x * flickProjection,
            y: frame.y + velocity.y * flickProjection,
            width: frame.width,
            height: frame.height
        )
        let index = pickScreen(for: projected, screens: screens)
        let releaseIndex = pickScreen(for: frame, screens: screens)
        let corner = flickedCorner(
            velocity: velocity,
            release: frame,
            screen: screens[releaseIndex].visible
        )
        return OverlayPlacement(
            state: OverlayLayoutState(corner: corner, isTucked: false),
            screenIndex: index
        )
    }

    public static func layout(
        afterDrag frame: OverlayRect,
        velocity: OverlayVelocity,
        screen: OverlayRect,
        tuckThreshold: Double = tuckThreshold
    ) -> OverlayLayoutState {
        layout(
            afterDrag: frame,
            velocity: velocity,
            screens: [OverlayScreen(screen)],
            tuckThreshold: tuckThreshold
        ).state
    }

    /// Speed from drag positions in the last `window` seconds. Older samples are ignored.
    public static func velocity(
        samples: [OverlayDragSample],
        window: Double = flickVelocityWindow
    ) -> OverlayVelocity {
        guard window > 0, let last = samples.max(by: { $0.time < $1.time }) else { return .zero }
        let start = last.time - window
        let spanned = samples.filter { $0.time >= start && $0.time <= last.time }
        guard let first = spanned.min(by: { $0.time < $1.time }) else { return .zero }
        let dt = last.time - first.time
        guard dt > 0, dt.isFinite else { return .zero }
        let vx = (last.x - first.x) / dt
        let vy = (last.y - first.y) / dt
        guard vx.isFinite, vy.isFinite else { return .zero }
        return OverlayVelocity(x: vx, y: vy)
    }

    /// Corner a flick is heading toward. Positive x is trailing, positive y is up.
    /// An axis inside `axisDeadzone` keeps the side of `release` on `screen`.
    public static func flickedCorner(
        velocity: OverlayVelocity,
        release frame: OverlayRect,
        screen: OverlayRect,
        axisDeadzone: Double = flickAxisDeadzone
    ) -> OverlayCorner {
        let current = nearestCorner(of: frame, screen: screen)
        let leading: Bool
        if abs(velocity.x) < axisDeadzone {
            switch current {
            case .topLeading, .bottomLeading: leading = true
            case .topTrailing, .bottomTrailing: leading = false
            }
        } else {
            leading = velocity.x < 0
        }
        let top: Bool
        if abs(velocity.y) < axisDeadzone {
            switch current {
            case .topLeading, .topTrailing: top = true
            case .bottomLeading, .bottomTrailing: top = false
            }
        } else {
            top = velocity.y > 0
        }
        switch (leading, top) {
        case (true, true): return .topLeading
        case (false, true): return .topTrailing
        case (true, false): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    /// Ease-out whose initial speed matches `velocity` when the duration fits in range.
    /// The curve ends at rest. Control points stay inside the unit square, so the card does not pass the corner.
    /// A very slow or very fast release clamps the duration; the slope then stays in 1.5...3.
    public static func glide(
        from release: OverlayRect,
        to parked: OverlayRect,
        velocity: OverlayVelocity
    ) -> OverlayGlide {
        let distance = hypot(parked.x - release.x, parked.y - release.y)
        let speed = velocity.speed
        let neutral = OverlayGlide(duration: 0.22, initialSlope: 2)
        guard distance > 0.5, speed > 1, speed.isFinite else { return neutral }
        let matched = 2 * distance / speed
        let duration = min(glideMaximumDuration, max(glideMinimumDuration, matched))
        let slope = min(3, max(1.5, speed * duration / distance))
        return OverlayGlide(duration: duration, initialSlope: slope)
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
