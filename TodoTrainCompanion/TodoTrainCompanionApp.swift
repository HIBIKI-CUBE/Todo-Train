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
    }
}

@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    let runtime = CompanionMacRuntime()
}
