# TodoTrainWidget

Xcode ターゲット `TodoTrainWidget`（Widget Extension）がプロジェクトに含まれています。メインターゲットへ Embed 済みです。

## 現状（AlarmKit）

`TodoTrainWidgetBundle`（`@main`）は **AlarmKit カウントダウン Live Activity のみ**を公開しています。

| ファイル | ターゲット | 内容 |
|----------|------------|------|
| `TodoTrainWidgetBundle.swift` | Extension | `@main` WidgetBundle |
| `TodoTrainAlarmLiveActivity.swift` | Extension | Lock Screen / Dynamic Island / StandBy |
| `TodoTrainAlarmMetadata.swift` | **App + Extension** | 共有 metadata |
| `Info.plist` | Extension | WidgetKit + Live Activities |
| `TodoTrainWidget.swift` | （未接続） | ホーム画面 Widget プレースホルダ |
| `README.md` | （除外） | 本ファイル |

手順の詳細は [docs/11-v2-alarmkit-setup.md](../docs/11-v2-alarmkit-setup.md)。

## ホーム画面 Widget（後続）

1. `TodoTrainWidget.swift` を Extension ターゲットの membership に戻す
2. `TodoTrainWidgetBundle` に `TodoTrainWidget()` を追加
3. App Group + `WidgetCenter.reloadTimelines` で実データ接続

## v1 表示（予定）

- 小: 運行中 / 運休、停車 n 件
- 中: 上記 + 今日の集中ざっくり（プレースホルダ）
