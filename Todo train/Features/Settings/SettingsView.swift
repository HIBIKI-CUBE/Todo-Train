//
//  SettingsView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionManager.self) private var sessionManager
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
                Text("停車中に置いておける切符の枚数です。上限を超えると整理シートが開きます。")
            }

            Section {
                Toggle("充電中は画面を消さない", isOn: Binding(
                    get: { settings.keepAwakeWhileChargingInFocus },
                    set: { settings.keepAwakeWhileChargingInFocus = $0 }
                ))
            } header: {
                Text("フォーカス")
            } footer: {
                Text("発車中かつ充電中のとき、自動ロックしません。")
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
                Text("見積もり到達時に AlarmKit で強制通知します（Silent / Focus を突破）。StandBy のカウントダウン表示にも使います。停車するとベルは消え、再乗車で残り時間から再スケジュールします。拒否された場合はローカル通知にフォールバックします。")
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
            .environment(DeletionUndoCenter())
            .modelContainer(container)
    }
}
