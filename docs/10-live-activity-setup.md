# Live Activity — Xcode セットアップ

`Todo train/Features/LiveActivity/` に ActivityKit 連携コードがあります。Mac で次を確認してください。

1. メインターゲットの **Signing & Capabilities** → **Live Activities** を有効化
2. `Info.plist` に `NSSupportsLiveActivities` = `YES`（未設定なら追加）
3. `SessionManager` は発車・停車・到着で `LiveActivityManager` を呼び出します（`#if canImport(ActivityKit)`）

## 動作

- **発車**: LA 開始（タイトル + 残時間カウントダウン）
- **停車 / 到着 / 途中下車 / 放棄**: LA 終了
- **超過**: `isOvertime` フラグで表示更新

全日運行の LA は作りません（8 時間制限。`07-research.md` 参照）。

## App Intent（任意・後続）

停車 / 到着の App Intent は v1 では未実装。DB が真実源のため、Intent 失敗時もセッションは整合します。
