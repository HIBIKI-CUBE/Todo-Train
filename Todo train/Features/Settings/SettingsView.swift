//
//  SettingsView.swift
//  Todo train
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

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
                Text("見積もり到達時に AlarmKit で強制通知します（Silent / Focus を突破）。StandBy のカウントダウン表示にも使われます。拒否された場合はローカル通知のみです。")
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
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppSettings.shared)
    }
}
