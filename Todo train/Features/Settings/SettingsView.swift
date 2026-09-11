//
//  SettingsView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionManager.self) private var sessionManager
    @Environment(CompanionSyncRuntime.self) private var runtime
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Form {
            Section {
                Picker("停車上限", selection: Binding(
                    get: { settings.pauseLimit },
                    set: { settings.pauseLimit = $0 }
                )) {
                    Text("2 枚").tag(2)
                    Text("3 枚").tag(3)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("停車")
            } footer: {
                Text("停車して置ける枚数です。上限に達すると新しい切符は発車できません。停車そのものはいつでもできます。再乗車もできます。")
            }

            Section {
                Toggle("充電中は画面を消さない", isOn: Binding(
                    get: { settings.keepAwakeWhileChargingInFocus },
                    set: { settings.keepAwakeWhileChargingInFocus = $0 }
                ))
                Toggle("車内放送", isOn: Binding(
                    get: { settings.cabinAnnouncementsEnabled },
                    set: { settings.cabinAnnouncementsEnabled = $0 }
                ))
            } header: {
                Text("フォーカス")
            } footer: {
                Text("発車中かつ充電中のとき、自動ロックしません。車内放送は長い乗務の途中に短い問いを出します。アプリを他アプリへ離れたときは列車側で一度だけ知らせます。")
            }
            .onChange(of: settings.cabinAnnouncementsEnabled) { _, _ in
                sessionManager.syncCabinAnnouncementsWithSettings()
            }

            Section {
                Toggle("超過時のシステム音", isOn: Binding(
                    get: { settings.overtimeSoundEnabled },
                    set: { settings.overtimeSoundEnabled = $0 }
                ))
            } header: {
                Text("超過")
            } footer: {
                Text("見積もりを過ぎたとき、一度だけアラート音を鳴らします。")
            }

            Section {
                Toggle("終了ベル（AlarmKit）", isOn: Binding(
                    get: { settings.endBellEnabled },
                    set: { settings.endBellEnabled = $0 }
                ))
            } header: {
                Text("終了ベル")
            } footer: {
                Text("見積もり到達時に AlarmKit で強制通知します（Silent / Focus を突破）。StandBy のカウントダウン表示にも使います。停車中も Live Activity は残り、再乗車できます。別切符を発車すると切り替わります。2 時間置くと Live Activity だけ消え、切符は停車のままです。拒否された場合はローカル通知にフォールバックします。")
            }
            .onChange(of: settings.endBellEnabled) { _, _ in
                sessionManager.syncEndBellWithSettings()
            }

            Section {
                NavigationLink {
                    TagManagerView()
                } label: {
                    Label("タグ管理", systemImage: "tag")
                }
            } header: {
                Text("データ")
            }

            Section {
                if runtime.isPaired {
                    LabeledContent("Mac") {
                        Text("つながっている")
                            .foregroundStyle(TrainTheme.muted)
                    }
                    Button("この Mac との連携を解除", role: .destructive) {
                        try? runtime.unpair()
                    }
                } else {
                    NavigationLink {
                        CompanionPairingView()
                    } label: {
                        Label("この Mac とつなぐ", systemImage: "laptopcomputer")
                    }
                }
                TextField("リレー URL", text: Binding(
                    get: { settings.companionRelayURLString },
                    set: { settings.companionRelayURLString = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                if let status = runtime.lastStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(TrainTheme.muted)
                }
            } header: {
                Text("Mac")
            } footer: {
                Text("画面を Mac に向ける一動作でつなぎます。この Mac だけが読めます。リレーは暗号化文だけ運びます。")
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(
            TrainLayout.navigationBarTitleDisplayMode(verticalSizeClass: verticalSizeClass)
        )
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let manager = SessionManager(modelContext: container.mainContext)
    return NavigationStack {
        SettingsView()
            .environment(AppSettings.shared)
            .environment(manager)
            .environment(CompanionSyncRuntime())
            .environment(DeletionUndoCenter())
            .modelContainer(container)
    }
}
