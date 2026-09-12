import AppKit
import SwiftUI
import TodoTrainSync

final class CompanionRideOverlayPanel: NSPanel {
    init() {
        let size = RideOverlayGeometry.cardSize.nsSize
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        isRestorable = false
        tabbingMode = .disallowed
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .fullScreenDisallowsTiling,
            .stationary,
            .ignoresCycle,
        ]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        let locked = size
        minSize = locked
        maxSize = locked
        contentMinSize = locked
        contentMaxSize = locked
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var rect = frameRect
        rect.size = RideOverlayGeometry.cardSize.nsSize
        return rect
    }
}

final class OverlayRootView: NSView {
    var onHover: ((Bool) -> Void)?
    var onDragChanged: ((_ mouse: NSPoint, _ startFrame: NSRect, _ startMouse: NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var onClick: ((NSPoint) -> Void)?
    var isTucked = false
    var edge = OverlayEdge.trailing

    private var tracking: NSTrackingArea?
    private var dragStartMouse: NSPoint?
    private var dragStartFrame: NSRect?
    private var isDragging = false

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        subviews.forEach { $0.frame = bounds }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if isTucked {
            let path = NSBezierPath(roundedRect: peekTabRect, xRadius: 10, yRadius: 10)
            return path.contains(point) ? self : nil
        }
        let radius = CGFloat(RideOverlayGeometry.cornerRadius)
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        guard path.contains(point) else { return nil }
        return self
    }

    private var peekTabRect: NSRect {
        let reveal = CGFloat(RideOverlayGeometry.peekReveal)
        switch edge {
        case .leading:
            return NSRect(x: bounds.width - reveal, y: 0, width: reveal, height: bounds.height)
        case .trailing:
            return NSRect(x: 0, y: 0, width: reveal, height: bounds.height)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: isTucked ? peekTabRect : bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        if isDragging { return }
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window?.frame
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse = dragStartMouse, let startFrame = dragStartFrame else { return }
        let mouse = NSEvent.mouseLocation
        let distance = hypot(mouse.x - startMouse.x, mouse.y - startMouse.y)
        if !isDragging {
            if distance < 4 { return }
            isDragging = true
            onHover?(false)
        }
        onDragChanged?(mouse, startFrame, startMouse)
    }

    override func mouseUp(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let dragged = isDragging
        isDragging = false
        dragStartMouse = nil
        dragStartFrame = nil
        if dragged {
            onDragEnded?(mouse)
            return
        }
        onClick?(convert(event.locationInWindow, from: nil))
    }
}

enum OverlayLayoutPersisting {
    static let cornerKey = "companion.overlay.corner"
    static let tuckedKey = "companion.overlay.tucked"
    static let screenKey = "companion.overlay.screenID"

    static func load(_ defaults: UserDefaults) -> OverlayLayoutState {
        let corner = OverlayCorner(rawValue: defaults.string(forKey: cornerKey) ?? "") ?? .bottomTrailing
        return OverlayLayoutState(corner: corner, isTucked: defaults.bool(forKey: tuckedKey))
    }

    static func save(_ state: OverlayLayoutState, screenID: UInt32, to defaults: UserDefaults) {
        defaults.set(state.corner.rawValue, forKey: cornerKey)
        defaults.set(state.isTucked, forKey: tuckedKey)
        defaults.set(Int(screenID), forKey: screenKey)
    }

    static func screenID(_ defaults: UserDefaults) -> UInt32 {
        UInt32(defaults.integer(forKey: screenKey))
    }
}

extension OverlayRect {
    init(_ rect: NSRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    var nsRect: NSRect {
        NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

extension OverlayScreen {
    init(_ screen: NSScreen) {
        self.init(display: OverlayRect(screen.frame), visible: OverlayRect(screen.visibleFrame))
    }
}

extension OverlaySize {
    var nsSize: NSSize { NSSize(width: CGFloat(width), height: CGFloat(height)) }
}

extension NSScreen {
    var overlayDisplayID: UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
