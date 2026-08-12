# TodoTrainWidget

Xcode ターゲット `TodoTrainWidget`（Widget Extension）がプロジェクトに含まれています。メインターゲットへ Embed 済みです。

## 現状（AlarmKit）

`TodoTrainWidgetBundle`（`@main`）は **AlarmKit カウントダウン Live Activity のみ**を公開しています。

| ファイル | ターゲット | 内容 |
|----------|------------|------|
| `TodoTrainWidgetBundle.swift` | Extension | `@main` WidgetBundle |
| `TodoTrainAlarmLiveActivity.swift` | Extension | タイマー UI + Intent 操作ボタン |
| `EndBellIntents.swift` | **App + Extension** | 停車 / 再乗車 / キャンセル / Stop |
| `TodoTrainAlarmMetadata.swift` | **App + Extension** | `sessionID` + `ticketTitle` |
| `Assets.xcassets` | Extension | AccentColor（rail tint） |
| `Info.plist` | Extension | WidgetKit + Live Activities |
| `TodoTrainWidget.swift` | （未接続） | ホーム画面 Widget プレースホルダ |

**操作:** カスタム LA では `Button(intent:)` が必須。`AlarmPresentation` の pause/resume はシステムテンプレート用フォールバックです。

手順: [docs/11-v2-alarmkit-setup.md](../docs/11-v2-alarmkit-setup.md)。
