# 08 — 現状ステータス（MVP 完了）

最終更新: 2026-08-12（Sprint 10 完了後）

## 結論

**MVP（Sprint 1–10）は実装完了**。次は **v1**（[09-v1-implementation.md](09-v1-implementation.md)）。

## 完了したスプリント

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
  Core/
    Session/     SessionManager, Clock, PauseLimitGuard, OverrideCounter
    Notifications/ OvertimeNotifier, OvertimeSchedule
    Estimate/    EstimateHeuristic
  Models/        Ticket, WorkSession, ServiceDay, Tag, TaskLineage, Enums
  Features/
    Hub/         HubView, QuickAddBar, ServiceSummaryBar, TicketCardView(未接続)
    Focus/       FocusView, FocusControls, OvertimeOverlay
    Arrival/     PauseLimitSheet, RemainingTicketsCanvas, TicketLineageService, SafetyLock*
    History/     HistoryView, HistorySessionRow, DailyStatsHeader, HistoryStats
    Tags/        TagManager, TagEditor, TagChip, TagPalette
    TicketDetail/
    Service/     ServiceEndSheet
  DesignSystem/  EstimateChips
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
| `TicketCardView` | ファイルはあるが Hub はインライン UI。v1 で見た目刷新可 |
| 挿入位置ピッカー | デフォルト末尾のみ。上級操作は薄い |
| 延長「なぜ」 | チップのみ。理由フィールドは薄い/未接続の可能性 |
| Settings 画面 | 停車上限は定数 2。設定 UI なし → **v1** |
| CloudKit | entitlement あり・未使用 |
| Live Activity / Widget | 未着手 → **v1** |

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
