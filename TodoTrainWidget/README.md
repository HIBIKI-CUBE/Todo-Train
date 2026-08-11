# TodoTrainWidget

Xcode ターゲット `TodoTrainWidget`（Widget Extension）がプロジェクトに含まれています。メインターゲットへ Embed 済みです。

## 公開 Widget

`TodoTrainWidgetBundle`（`@main`）:

| Widget | 用途 |
|--------|------|
| `TodoTrainHomeWidget` | ホーム画面（運行中/運休・停車数・今日の集中） |
| `TodoTrainSessionLiveActivity` | 発車中 Session LA（終了ベル OFF 時） |
| `TodoTrainAlarmLiveActivity` | AlarmKit StandBy カウントダウン（終了ベル ON 時） |

**排他:** `SessionManager` は `endBellEnabled` のとき Session LA を出さず AlarmKit LA のみにします（同時に 2 本張らない）。

## 共有 / ターゲット

| ファイル | ターゲット | 内容 |
|----------|------------|------|
| `TodoTrainWidgetBundle.swift` | Extension | `@main` WidgetBundle |
| `TodoTrainWidget.swift` | Extension | ホーム Widget |
| `TodoTrainSessionLiveActivity.swift` | Extension | Session LA UI |
| `TodoTrainAlarmLiveActivity.swift` | Extension | Alarm LA UI + Intent ボタン |
| `TodoTrainActivityAttributes.swift` | **App + Extension** | Session LA attributes |
| `WidgetSnapshot.swift` | **App + Extension** | App Group スナップショット |
| `EndBellIntents.swift` | **App + Extension** | 停車 / 再乗車 / キャンセル / Stop |
| `TodoTrainAlarmMetadata.swift` | **App + Extension** | `sessionID` + `ticketTitle` |
| `Assets.xcassets` | Extension | AccentColor |
| `TodoTrainWidget.entitlements` | Extension | App Group |
| `Info.plist` | Extension | WidgetKit + Live Activities |

App Group: `group.dev.hibiki-cube.Todo-train`

手順: [docs/10-live-activity-setup.md](../docs/10-live-activity-setup.md) / [docs/11-v2-alarmkit-setup.md](../docs/11-v2-alarmkit-setup.md)。
