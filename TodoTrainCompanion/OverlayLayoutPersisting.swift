import AppKit
import Foundation
import TodoTrainSync

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
