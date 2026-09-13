import SwiftUI

@main
struct TodoTrainCompanionApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            CompanionPopover()
                .environment(delegate.runtime)
        } label: {
            CompanionBarLabel()
                .environment(delegate.runtime)
                .onAppear {
                    CompanionStatusItemRightClick.install()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            RelaySettingsView(runtime: delegate.runtime)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    CompanionSettingsOpener.dismissPopover?()
                }
                .onDisappear {
                    CompanionSettingsOpener.restoreAccessoryPolicyIfNeeded()
                }
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Todo train を終了") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    let runtime = CompanionMacRuntime()
    private var overlay: CompanionRideOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CompanionStatusItemRightClick.install()
        overlay = CompanionRideOverlayController(runtime: runtime)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(macWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(macDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(macScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(macScreensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(macScreensaverDidStart),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        distributed.addObserver(
            self,
            selector: #selector(macScreensaverDidStop),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func macWillSleep(_ notification: Notification) {
        runtime.noteSystemSleep()
    }

    @objc private func macDidWake(_ notification: Notification) {
        runtime.noteSystemWake()
    }

    @objc private func macScreensDidSleep(_ notification: Notification) {
        runtime.noteScreensSleep()
    }

    @objc private func macScreensDidWake(_ notification: Notification) {
        runtime.noteScreensWake()
    }

    @objc private func macScreensaverDidStart(_ notification: Notification) {
        runtime.noteScreensaverDidStart()
    }

    @objc private func macScreensaverDidStop(_ notification: Notification) {
        runtime.noteScreensaverDidStop()
    }
}
