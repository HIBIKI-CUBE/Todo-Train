import SwiftUI
import TodoTrainSync

struct CompanionPopover: View {
    @Environment(CompanionMacRuntime.self) private var runtime

    var body: some View {
        Group {
            if !runtime.isPaired {
                CompanionPairingPane()
            } else {
                pairedBody
            }
        }
        .padding(16)
    }

    private var pairedBody: some View {
        let view = runtime.presentation
        return VStack(alignment: .leading, spacing: 12) {
            Text(view.popoverTitle)
                .font(.headline)
                .textSelection(.enabled)
            Text(view.popoverDetail)
                .font(.title2.monospacedDigit())
                .foregroundStyle(view.isOvertime ? .orange : .primary)

            if let failure = view.failureLine {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let status = runtime.lastStatus, runtime.connection == .disconnected {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if view.canPause {
                Button("停車") {
                    Task { await runtime.sendPause() }
                }
                .keyboardShortcut(.defaultAction)
            } else if view.isSending {
                Text("iPhone に送った")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 280)
    }
}

struct CompanionBarLabel: View {
    @Environment(CompanionMacRuntime.self) private var runtime

    var body: some View {
        let title = runtime.presentation.barTitle
        HStack(spacing: 6) {
            Image(systemName: "tram.fill")
            if let title {
                Text(title)
                    .monospacedDigit()
            }
        }
    }
}

struct RelaySettingsView: View {
    @Bindable var runtime: CompanionMacRuntime

    var body: some View {
        Form {
            TextField("リレー URL", text: $runtime.relayURLString)
            Toggle("ログイン時に起動", isOn: $runtime.loginAtStartup)
            Text("この Mac だけが読める。解除は iPhone の設定。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
