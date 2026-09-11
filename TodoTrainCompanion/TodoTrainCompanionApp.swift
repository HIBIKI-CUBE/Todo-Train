import SwiftUI

@main
struct TodoTrainCompanionApp: App {
    @State private var runtime = CompanionMacRuntime()

    var body: some Scene {
        MenuBarExtra {
            CompanionPopover()
                .environment(runtime)
        } label: {
            CompanionBarLabel()
                .environment(runtime)
        }
        .menuBarExtraStyle(.window)

        Window("ペアリング", id: "pairing") {
            PairingWindow()
                .environment(runtime)
        }
        .windowResizability(.contentMinSize)

        Settings {
            RelaySettingsView(runtime: runtime)
        }
    }
}
