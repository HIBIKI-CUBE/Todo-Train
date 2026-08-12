# 08 — 現状ステータス

最終更新: 2026-08-12（v1 実装中）

## 結論

**MVP（Sprint 1–10）は実装完了**。**v1** を実装中（[09-v1-implementation.md](09-v1-implementation.md)）。

### v1 進捗（Cloud Agent）

| WP | 状態 | 備考 |
|----|------|------|
| WP-A Settings | 実装済 | 停車上限 2/3、超過音 ON/OFF |
| WP-B History | 実装済 | 検索 + 今日に追加 |
| WP-C Reorder | 実装済 | フィルタ強調 + D&D |
| WP-D dueDate | 実装済 | 任意期限、自動ソートなし |
| WP-E Custom estimate | 実装済 | 1–60 分任意入力 |
| WP-F Live Activity | **配線済** | Session LA UI + AlarmKit 排他。実機確認は [10-live-activity-setup.md](10-live-activity-setup.md) |
| WP-G Widget | **配線済** | App Group スナップショット。実機でホーム追加確認 |
| WP-H AI / PCC | stub 済 | `CoachingEngine` + Heuristic |
| WP-I CloudKit | 未着手 | 独立 PR 推奨 |

### v2 進捗（AlarmKit PR）

| 項目 | 状態 |
|------|------|
| AlarmKit 終了ベル | コード済（`AlarmScheduling` + Settings トグル） |
| StandBy カウントダウン LA | **操作付き polish + 同期安定化済**（停車/再乗車/キャンセル抑制・上限時臨時停車）。実機検証待ち（[11-v2-alarmkit-setup.md](11-v2-alarmkit-setup.md)） |
| 週次レポート | `WeeklyReportView` + 純関数テスト |

**ブランチ:** `feature/alarmkit-display`（UI polish は `feature/ios-native-ui`）。

**注意:** v1 PR（#2）の Mac 検証前にマージする場合、SessionManager / LA 配線の前提が未確認です。

### UI polish（stack PR）

| 項目 | 状態 |
|------|------|
| Design tokens | adaptive `TrainTheme` / Focus 用 `TrainChrome` |
| Tab ナビ | 切符 / 履歴 / 設定 |
| Quick Add | シート + Form（`QuickAddSheet`） |
| Hub / History / Settings / Reorder | 標準 List/Form、ダーク対応 |
| 切符・履歴の削除 | Hub スワイプ / 詳細ボタン / 履歴行スワイプ（物理削除） |
| 方針ドキュメント | [12-ui-design.md](12-ui-design.md) |

## MVP 完了マップ（Sprint 1–10）

| Sprint | 内容 | 主な成果物 |
|--------|------|------------|
| 1 | SessionManager + 運行 | `Core/Session/*`, モデル, 単体テスト |
| 2 | Focus + 超過 | `Features/Focus/*` |
| 3 | Hub + FAB | `Features/Hub/*`, `TicketDetail` |
| 4 | 停車上限 + 途中下車キャンバス | `PauseLimitSheet`, `RemainingTicketsCanvas`, `TicketLineageService` |
| 5 | 履歴 + 乗り継ぎリンク | `Features/History/*` |
| 6 | タグ UI | `Features/Tags/*` |
| 7 | 超過ローカル通知 | `Core/Notifications/*` |
| 8 | 臨時停車 Override | `SafetyLockOverrideControl`, `forcePause`, `OverrideCounter` |
| 9 | Heuristic 見積もり | `Core/Estimate/EstimateHeuristic.swift` |
| 10 | 運行終了フロー | `Features/Service/ServiceEndSheet.swift` |

## ディレクトリ（実装の地図）

```
Todo train/
  App/AppModelContainer.swift
  ContentView.swift   TabView（切符 / 履歴 / 設定）+ Focus cover
  Core/
    Session/     SessionManager, Clock, PauseLimitGuard, OverrideCounter
    Notifications/ OvertimeNotifier, OvertimeSchedule
    Estimate/    EstimateHeuristic
  Models/        Ticket, WorkSession, ServiceDay, Tag, TaskLineage, Enums
  Features/
    Hub/         HubView, QuickAddSheet, ServiceSummaryBar, TicketCardView
    Focus/       FocusView, FocusControls, OvertimeOverlay
    Arrival/     PauseLimitSheet, RemainingTicketsCanvas, TicketLineageService, SafetyLock*
    History/     HistoryView, HistorySessionRow, DailyStatsHeader, HistoryStats
    Tags/        TagManager, TagEditor, TagChip, TagPalette
    TicketDetail/
    Service/     ServiceEndSheet
    Settings/    SettingsView
  DesignSystem/  EstimateChips, TrainTheme, TrainChrome
Todo trainTests/  SessionManager, HistoryStats, Tag, Overtime, Override, EstimateHeuristic, Lineage
```

## 動作するユーザーフロー

1. 運行開始 → FAB で切符掃き出し（見積もり + 任意タグ）
2. 発車 → Focus（停車 / 到着 / 延長 / 超過）
3. 停車上限 → 解決シート / 途中下車キャンバス / 臨時停車
4. 履歴で振り返り・乗り継ぎリンク
5. 運行終了 → 停車中の持ち越し / 途中下車 / 放棄

## 既知のギャップ（意図的）

| 項目 | 備考 |
|------|------|
| 挿入位置ピッカー | **実装済**（Quick Add / 乗り継ぎ） |
| 延長「なぜ」 | **実装済**（SessionExtension + 理由チップ） |
| Settings 画面 | 停車上限・終了ベル・超過音 |
| CloudKit | entitlement あり・未使用（本スコープ外） |
| Live Activity / Widget | Session LA + Home Widget 配線済。終了ベル ON 時は AlarmKit 排他 |

## テスト

- スキーム: `Todo train`
- ユニット: `Todo trainTests`（Swift Testing）
- ローカル検証例（Mac + Xcode）:

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
