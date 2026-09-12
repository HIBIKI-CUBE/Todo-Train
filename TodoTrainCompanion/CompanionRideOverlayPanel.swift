import AppKit
import TodoTrainSync

final class CompanionRideOverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: RideOverlayGeometry.cardSize.width,
                height: RideOverlayGeometry.cardSize.height
            ),
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
        animationBehavior = .utilityWindow
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
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
        NSRect(x: x, y: y, width: width, height: height)
    }
}

extension NSScreen {
    var overlayDisplayID: UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
