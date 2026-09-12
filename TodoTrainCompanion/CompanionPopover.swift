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
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if let identity = identityCaption {
                        Text(identity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text(view.popoverTitle)
                        .font(.headline)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                CompanionSettingsGear()
            }

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

            if view.canReconnect {
                Button("つなぎ直す") {
                    runtime.reconnect()
                }
                .buttonStyle(.bordered)
            }

            if view.canPause {
                Button("停車") {
                    Task { await runtime.sendPause() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(view.isSending)
            } else if view.canResume {
                Button("再乗車") {
                    Task { await runtime.sendResume() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(view.isSending)
            }
        }
        .frame(minWidth: 280)
    }

    private var identityCaption: String? {
        runtime.companionName ?? runtime.pairingShortID
    }
}

struct CompanionBarLabel: View {
    @Environment(CompanionMacRuntime.self) private var runtime
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let title = runtime.presentation.barTitle
        HStack(spacing: 6) {
            Image(systemName: "tram.fill")
            if let title {
                Text(title)
                    .monospacedDigit()
            }
        }
        .onAppear {
            CompanionSettingsOpener.openSettings = openSettings
            CompanionStatusItemRightClick.install()
        }
    }
}

struct RelaySettingsView: View {
    @Bindable var runtime: CompanionMacRuntime
    @State private var confirmUnpair = false

    var body: some View {
        Form {
            Section("連携") {
                if runtime.isPaired {
                    LabeledContent("この Mac") {
                        Text(runtime.companionName ?? MacComputerName.current())
                    }
                    if let pairingShortID = runtime.pairingShortID {
                        LabeledContent("ペア") {
                            Text(pairingShortID)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    Button("この iPhone との連携を解除", role: .destructive) {
                        confirmUnpair = true
                    }
                } else {
                    Text("つながっていません")
                        .foregroundStyle(.secondary)
                }
            }

            Section("起動") {
                Toggle("ログイン時に起動", isOn: $runtime.loginAtStartup)
            }

            Section("リレー") {
                TextField("リレー URL", text: $runtime.relayURLString)
                Text("識別子が iPhone の設定と同じなら、この Mac とつながっています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .alert("連携を解除しますか？", isPresented: $confirmUnpair) {
            Button("解除する", role: .destructive) {
                runtime.unpair()
                CompanionSettingsOpener.close()
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("この Mac とのつながりを解除します。つなぎ直すときは、もう一度画面を向けます。")
        }
    }
}
