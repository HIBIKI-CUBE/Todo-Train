import AppKit
import SwiftUI

@MainActor
enum CompanionSettingsOpener {
    static var openSettings: OpenSettingsAction?
    static var dismissPopover: (() -> Void)?

    static func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            openSettings?()
        }
    }

    static func close() {
        for window in NSApp.windows where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
            window.close()
        }
        restoreAccessoryPolicyIfNeeded()
    }

    static func restoreAccessoryPolicyIfNeeded() {
        let settingsOpen = NSApp.windows.contains {
            $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" && $0.isVisible
        }
        if !settingsOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
enum CompanionStatusItemRightClick {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp, .leftMouseDown]) { event in
            guard isStatusItemEvent(event) else { return event }
            let controlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            if event.type == .rightMouseDown || controlClick {
                CompanionSettingsOpener.open()
                return nil
            }
            if event.type == .rightMouseUp {
                return nil
            }
            return event
        }
    }

    private static func isStatusItemEvent(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        let name = String(describing: type(of: window))
        if name.contains("StatusBar") || name.contains("StatusItem") {
            return true
        }
        return window.contentView?.subviews.contains(where: { $0 is NSStatusBarButton }) == true
    }
}

struct CompanionSettingsGear: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsLink {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        .help("設定")
        .accessibilityLabel("設定")
        .onAppear {
            CompanionSettingsOpener.openSettings = openSettings
            CompanionSettingsOpener.dismissPopover = { dismiss() }
        }
    }
}
