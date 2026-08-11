# Live Activity — Xcode セットアップ

Session（発車中）Live Activity と Home Widget の配線。

## Capability

1. メインターゲット **Signing & Capabilities**
   - **Live Activities**
   - **App Groups** → `group.dev.hibiki-cube.Todo-train`
2. `TodoTrainWidget` ターゲット
   - **App Groups** → 同じ ID
   - `Info.plist` に `NSSupportsLiveActivities` = YES（済）
3. メインアプリ `NSSupportsLiveActivities` = YES（済）

## 動作

| 条件 | 表示 |
|------|------|
| 発車中 & 終了ベル OFF | Session LA（タイトル + 残時間 / 超過） |
| 発車中 & 終了ベル ON | AlarmKit LA のみ（Session LA は終了） |
| 停車 / 到着 / 途中下車 / 放棄 | Session LA 終了 |

全日運行の LA は作りません（8 時間制限。`07-research.md` 参照）。

## Home Widget

`SessionManager.reconcile` が App Group にスナップショットを書き、`TodoTrainHomeWidget` が読みます（運行中/運休・停車数・今日の集中分）。

## App Intent（任意・後続）

Session LA からの停車 / 到着 Intent は未実装。AlarmKit 側は `EndBellIntents` 済み。DB が真実源です。
