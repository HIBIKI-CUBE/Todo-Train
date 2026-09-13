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
    private static var mouseMonitor: Any?

    static func install() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .rightMouseDown, .rightMouseUp, .leftMouseDown, .leftMouseUp,
        ]) { event in
            guard isStatusItemEvent(event) else { return event }
            let controlClick = event.modifierFlags.contains(.control)
                && (event.type == .leftMouseDown || event.type == .leftMouseUp)
            if event.type == .rightMouseDown || (event.type == .leftMouseDown && controlClick) {
                let captured = event
                DispatchQueue.main.async {
                    popMenu(with: captured)
                }
                return nil
            }
            if event.type == .rightMouseUp || (event.type == .leftMouseUp && controlClick) {
                return nil
            }
            return event
        }
    }

    private static func popMenu(with event: NSEvent) {
        CompanionSettingsOpener.dismissPopover?()
        guard let window = event.window, let view = window.contentView else { return }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = CompanionStatusItemMenuActions.shared

        let settings = NSMenuItem(
            title: "設定…",
            action: #selector(CompanionStatusItemMenuActions.openSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = target
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Todo train を終了",
            action: #selector(CompanionStatusItemMenuActions.quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = target
        menu.addItem(quit)
        return menu
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

@MainActor
private final class CompanionStatusItemMenuActions: NSObject {
    static let shared = CompanionStatusItemMenuActions()

    @objc func openSettings(_ sender: Any?) {
        CompanionSettingsOpener.open()
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
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
        .keyboardShortcut(",")
        .help("設定")
        .accessibilityLabel("設定")
        .onAppear {
            CompanionSettingsOpener.openSettings = openSettings
            CompanionSettingsOpener.dismissPopover = { dismiss() }
        }
    }
}
