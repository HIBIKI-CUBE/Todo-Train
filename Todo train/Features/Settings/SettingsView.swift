//
//  SettingsView.swift
//  Todo train
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            PlatformBackground()

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

                    Text("停車中に置いておける切符の枚数です。4 枚目は整理シートが開きます。")
                        .font(.caption)
                        .foregroundStyle(TrainTheme.muted)
                } header: {
                    Text("停車")
                }

                Section {
                    Toggle("超過時のシステム音", isOn: Binding(
                        get: { settings.overtimeSoundEnabled },
                        set: { settings.overtimeSoundEnabled = $0 }
                    ))

                    Text("見積もりを過ぎたとき、一度だけアラート音を鳴らします。")
                        .font(.caption)
                        .foregroundStyle(TrainTheme.muted)
                } header: {
                    Text("超過")
                }

                Section {
                    Toggle("終了ベル（AlarmKit）", isOn: Binding(
                        get: { settings.endBellEnabled },
                        set: { settings.endBellEnabled = $0 }
                    ))

                    Text("見積もり到達時に AlarmKit で強制通知します（Silent / Focus を突破）。StandBy のカウントダウン表示にも使われます。拒否された場合はローカル通知のみです。")
                        .font(.caption)
                        .foregroundStyle(TrainTheme.muted)
                } header: {
                    Text("終了ベル")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .tint(TrainTheme.rail)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppSettings.shared)
    }
}
