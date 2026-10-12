//
//  SettingsView.swift
//  Todo train
//

import SwiftUI
import SwiftData
import TodoTrainSync
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionManager.self) private var sessionManager
    @Environment(CompanionSyncRuntime.self) private var runtime
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var diagnosticExportError: String?
    @State private var didCopyBuild = false
    @State private var buildCopyGeneration = 0

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
                Text("停車して置ける枚数です。上限に達すると新しい切符は発車できませんが、停車と再乗車はいつでもできます。")
            }

            Section {
                Toggle("充電中は画面をつけたまま", isOn: Binding(
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
                Text("発車中に充電していると、自動ロックしません。車内放送は長い乗務の途中に短い問いを出し、ほかのアプリへ離れたときは列車側で一度だけ知らせます。")
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
                Text("見積もりに達すると、消音やフォーカス中でも AlarmKit で鳴らします（許可がないときは通常の通知になります）。StandBy のカウントダウンにも使い、停車中も 2 時間は Live Activity から再乗車できます。")
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
                Button {
                    exportDiagnosticData()
                } label: {
                    Label("診断データを書き出す", systemImage: "square.and.arrow.up")
                }
                if let diagnosticExportError {
                    Text(diagnosticExportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                LabeledContent(BuildInfoCopy.title) {
                    Text(LocalWireBuild.line)
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                }
                .onLongPressGesture {
                    copyBuildLine()
                }
                .accessibilityAction(named: "コピー") {
                    copyBuildLine()
                }
                if didCopyBuild {
                    Text(BuildInfoCopy.copied)
                        .font(.footnote)
                        .foregroundStyle(TrainTheme.muted)
                }
                Text(BuildInfoCopy.explanation)
                    .font(.footnote)
                    .foregroundStyle(TrainTheme.muted)
            } header: {
                Text("診断")
            } footer: {
                Text("題名などの中身は含まれません。")
            }

            Section {
                if runtime.isPaired {
                    LabeledContent("Mac") {
                        Text(runtime.companionName ?? "つながっています")
                    }
                    if let pairingShortID = runtime.pairingShortID {
                        LabeledContent("ペア") {
                            Text(pairingShortID)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
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
                Text("画面を向けた Mac だけが読めます。識別子が Mac 側と同じなら同じペアで、解除はどちらからでもできます。")
            }

            if settings.developerToolsUnlocked {
                Section {
                    Toggle("接近を常に出す", isOn: Binding(
                        get: { settings.forceApproachClearVisible },
                        set: { settings.forceApproachClearVisible = $0 }
                    ))
                    NavigationLink {
                        DeveloperForecastLogView()
                    } label: {
                        Text("予測の内部")
                    }
                    Button("開発者メニューを隠す") {
                        settings.developerToolsUnlocked = false
                    }
                    .foregroundStyle(.secondary)
                } header: {
                    Text("開発者")
                } footer: {
                    Text("「接近を常に出す」はこのメニューを開いているあいだだけ盤を出し、遊んでも戻ってきたときの報酬は減りません。「予測の内部」は、切符を持ち上げたときのオンデバイス予測の記録です。")
                }
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(
            TrainLayout.navigationBarTitleDisplayMode(verticalSizeClass: verticalSizeClass)
        )
        .safeAreaInset(edge: .bottom) {
            Text("Todo train")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .onTapGesture(count: AppSettings.developerUnlockTapCount) {
                    guard !settings.developerToolsUnlocked else { return }
                    settings.developerToolsUnlocked = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .accessibilityHidden(true)
        }
    }

    private func copyBuildLine() {
        UIPasteboard.general.string = LocalWireBuild.line
        buildCopyGeneration += 1
        didCopyBuild = true
        let generation = buildCopyGeneration
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard generation == buildCopyGeneration else { return }
            didCopyBuild = false
        }
    }

    private func exportDiagnosticData() {
        do {
            let data = try PDCAExport.jsonData(in: modelContext)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("todotrain-pdca.json")
            try data.write(to: url, options: .atomic)
            guard let presenter = Self.topViewController() else {
                diagnosticExportError = "書き出せませんでした"
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = presenter.view
                let bounds = presenter.view.bounds
                popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            diagnosticExportError = nil
            presenter.present(activity, animated: true)
        } catch {
            diagnosticExportError = "書き出せませんでした"
        }
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
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
            .environment(ArrivalForecastTraceLog.shared)
            .modelContainer(container)
    }
}
