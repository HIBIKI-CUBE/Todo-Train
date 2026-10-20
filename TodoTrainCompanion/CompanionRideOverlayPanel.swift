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
    var boardGestureEnabled: (() -> Bool)?
    var onBoardGesture: (() -> Void)?
    var isTucked = false
    var edge = OverlayEdge.trailing

    private var tracking: NSTrackingArea?
    private var dragStartMouse: NSPoint?
    private var dragStartFrame: NSRect?
    private var isDragging = false
    private var boardStart: NSPoint?
    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0

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
        let local = convert(event.locationInWindow, from: nil)
        if boardGestureEnabled?() == true, local.x >= CompanionRideOverlayController.handleWidth {
            boardStart = local
            dragStartMouse = nil
            dragStartFrame = nil
            isDragging = false
            return
        }
        boardStart = nil
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window?.frame
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard boardStart == nil else { return }
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
        if let start = boardStart {
            let local = convert(event.locationInWindow, from: nil)
            boardStart = nil
            if ArrivalGapBoardGesture.commits(
                translationX: local.x - start.x,
                translationY: local.y - start.y,
                cardWidth: bounds.width
            ) {
                onBoardGesture?()
            }
            return
        }
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

    override func scrollWheel(with event: NSEvent) {
        guard boardGestureEnabled?() == true else { return }
        if event.phase == .began {
            scrollX = 0
            scrollY = 0
        }
        if event.phase == .began || event.phase == .changed {
            scrollX += event.scrollingDeltaX
            scrollY += event.scrollingDeltaY
        }
        if event.phase == .ended {
            if ArrivalGapBoardGesture.commits(
                translationX: scrollX,
                translationY: scrollY,
                cardWidth: bounds.width
            ) {
                onBoardGesture?()
            }
            scrollX = 0
            scrollY = 0
        }
    }
}
