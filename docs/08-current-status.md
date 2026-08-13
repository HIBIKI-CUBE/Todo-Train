# 08 — 現状ステータス

最終更新: 2026-08-13（発行＝マルス券排出 / 到着＝スワイプ無効化）

## 結論

**MVP（Sprint 1–10）・v1・v2（AlarmKit / UI polish）は `develop` にマージ済み。**  
未着手は **CloudKit（WP-I）** のみ。実装マップと検証手順は本ファイルと [11-v2-alarmkit-setup.md](11-v2-alarmkit-setup.md) / [12-ui-design.md](12-ui-design.md) を参照。

定時の喜びは **エフェメラ**。到着は完了ジェスチャ（切符の無効化）で祝う。ストリークや定時率は出さない。超過で案内は取り下げない。

発行の単発祝祭はマルス 8.5cm 未使用券（[references/](references/)）。到着は同じ券面をスワイプで使用済みにする（`ArrivalInvalidateOverlay`）。

### v1 進捗

| WP | 状態 | 備考 |
|----|------|------|
| WP-A Settings | ✅ | 停車上限 2/3、超過音 ON/OFF |
| WP-B History | ✅ | 検索 + 今日に追加 |
| WP-C Reorder | ✅ | フィルタ強調 + D&D |
| WP-D dueDate | ✅ | 任意期限、自動ソートなし |
| WP-E Custom estimate | ✅ | 1–60 分任意入力 |
| WP-F Live Activity | ✅ | Session LA + AlarmKit 排他。[11](11-v2-alarmkit-setup.md) §6 で検証 |
| WP-G Widget | ✅ | App Group スナップショット |
| WP-H AI / PCC | stub 済 | `CoachingEngine` + Heuristic |
| WP-I CloudKit | 未着手 | 独立 PR 推奨 |

### v2 進捗

| 項目 | 状態 |
|------|------|
| AlarmKit 終了ベル | ✅ `AlarmScheduling` + Settings トグル |
| StandBy / Session LA | ✅ コックピット計器 UI + サイズ契約。検証は [11](11-v2-alarmkit-setup.md) §6 |
| 週次レポート | ✅ `WeeklyReportView` + 純関数テスト |
| UI polish | ✅ `TrainTheme` / `TrainChrome` / 横向き compact（[12](12-ui-design.md)） |
| 切符・履歴の削除 | ✅ フルスワイプ + バナー Undo（[12](12-ui-design.md)） |
| 定時到着 / 定時運行 | ✅ 到着は完了として案内。定時・早着はいい結果の見出し。超過でも取り下げない |

## ディレクトリ（実装の地図）

```
Todo train/
  ContentView.swift        TabView（切符 / 履歴 / 設定）+ Focus cover
  Core/
    Session/               SessionManager, TicketDeletion, DeletionUndo
    Alarms/                AlarmScheduling, EndBellDelivery, SessionEndSchedule
    Notifications/         OvertimeNotifier
    History/               HistorySearch, TicketReissue, WeeklyReport, Punctuality
    Settings/              AppSettings
    Coaching/              CoachingEngine
  DesignSystem/            TrainTheme, TrainChrome, TrainLayout, EstimateChips,
                           DeleteConfirmation, EstimateSnapMapping, EstimateSnapGauge,
                           TicketIssueEject, ArrivalInvalidateOverlay, PunctualityMomentOverlay,
                           MarsTicketSpec, MarsTicketView
  Features/
    Hub/                   HubView, QuickAddBar（親指発券帯）, ServiceSummaryBar
    Focus/                 FocusView, FocusControlsView, OvertimeSheet
    Arrival/               PauseLimitSheet, TransferCanvasPresenter
    History/               HistoryView, WeeklyReportView
    LiveActivity/          LiveActivityManaging
    Reorder/               ReorderView
    Settings/              SettingsView
TodoTrainWidget/           Home Widget + Session LA + Alarm LA
Todo trainTests/           26 ファイル（Swift Testing）
```

## 動作するユーザーフロー

1. 運行開始 → ツールバー `＋` で親指発券帯（Return / スナップ・ゲージで掃き出し）
2. 発車 → Focus（停車 / 到着 / 延長 / 超過）。到着したら短い案内。定時なら定時到着、早着なら早着
3. 停車上限 → 解決シート / 途中下車キャンバス / 臨時停車
4. 履歴で振り返り・乗り継ぎリンク・今日に追加（定時はバッジのみ）
5. 運行終了 → 停車中の持ち越し禁止 / 途中下車 / 放棄。遅延がなければ短い「定時運行」（早着可）
6. 終了ベル ON → AlarmKit LA（StandBy）/ OFF → Session LA

## 既知のギャップ（意図的）

| 項目 | 備考 |
|------|------|
| CloudKit | entitlement あり・未使用 |
| Session LA からの Intent | 未実装（Alarm LA は `EndBellIntents` 済み） |
| iPad 最適化 | v2 以降 |
| 乗り継ぎキャンバスのゲージ統一 | Phase 2（Quick Add のみ線形スナップ・ゲージ） |

## テスト

- スキーム: `Todo train`
- ユニット: `Todo trainTests`（Swift Testing）

```bash
SIM=<booted-iphone-simulator-udid>
xcodebuild build-for-testing -scheme "Todo train" \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath /tmp/TodoTrainDerived
xcodebuild test-without-building -scheme "Todo train" \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath /tmp/TodoTrainDerived \
  -only-testing:"Todo trainTests" \
  -parallel-testing-enabled NO
```

注意: シミュレータがハングすることがある。`simctl shutdown all` → 別デバイスで再 boot が有効。
