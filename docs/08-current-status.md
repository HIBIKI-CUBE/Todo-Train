# 08 — 現状ステータス

最終更新: 2026-09-12（リレー `todo-train.hibiki-cube.dev` / `dev.todo-train.hibiki-cube.dev`。Mac ペアリングはメニューバー吹き出し。確認は [16](16-wakeup-checklist.md)）

## 結論

**MVP（Sprint 1–10）・v1・v2（AlarmKit / UI polish）・車内放送は実装済み。**  
**CloudKit（WP-I）** はスキーマとゲート付きローカル store まで。Mac 土管には使わない。同期の Linux 芯（契約・リレー・Swift パッケージ・E2E）は完了。構成は [13-sync-mac-companion.md](13-sync-mac-companion.md)。Mac の画面は [14-mac-companion-ux.md](14-mac-companion-ux.md)（確認 1 は吹き出しで確定。2–6 は提案値）。実装マップと検証手順は本ファイルと [11-v2-alarmkit-setup.md](11-v2-alarmkit-setup.md) / [12-ui-design.md](12-ui-design.md) を参照。

定時の喜びは **エフェメラ**。到着は完了ジェスチャ（切符の無効化）で祝う。ストリークや定時率は出さない。超過で案内は取り下げない。

発行の単発祝祭はマルス 8.5cm 未使用券（[references/](references/)）。到着は同じ券面をスワイプで使用済みにする（`ArrivalInvalidateOverlay`）。

### v1 進捗

| WP | 状態 | 備考 |
|----|------|------|
| WP-A Settings | ✅ | 停車上限 2/3（新規発車ゲート）、超過音、充電中は消さない、車内放送 |
| WP-B History | ✅ | 検索 + 今日に追加 |
| WP-C Reorder | ✅ | フィルタ強調 + D&D |
| WP-D dueDate | ✅ | 任意期限、自動ソートなし |
| WP-E Custom estimate | ✅ | 1–60 分任意入力 |
| WP-F Live Activity | ✅ | Session LA + AlarmKit 排他。停車中も LA を残す（2h） |
| WP-G Widget | ✅ | App Group スナップショット |
| WP-H AI / PCC | 部分 | 分割・日次レビューは stub。車内放送 1 行は `OnDeviceCoachingEngine` |
| WP-I CloudKit | ゲート維持 | unique 削除・`boardedDeviceID`・`.none` store。Mac 土管には使わない |

### 同期（Linux 芯）

| ID | 状態 | 備考 |
|----|------|------|
| SYNC-0 契約 | ✅ | `sync/contract/` |
| SYNC-1 リレー | ✅ | `sync/worker/`。CI `sync-worker`。本番 `https://todo-train.hibiki-cube.dev`、develop `https://dev.todo-train.hibiki-cube.dev`。secrets が無いと deploy は skip |
| SYNC-2 Swift 芯 | ✅ | `Packages/TodoTrainSync`。Mac は SYNC-4、iOS は SYNC-3 でリンク。CI `sync-swift` |
| SYNC-5 Linux E2E | ✅ | `sync/e2e/run.sh`。CI `sync-swift` |
| SYNC-3 iOS UI | `develop` 済み。実機待ち | Settings セルフィー + `SessionManager` 配線（#35） |
| SYNC-4 macOS | `develop` 済み。実機待ち | メニューバー吹き出しで即ペアリング。正方カメラ枠（#39） |

### v2 進捗

| 項目 | 状態 |
|------|------|
| AlarmKit 終了ベル | ✅ `AlarmScheduling` + Settings トグル |
| StandBy / Session LA | ✅ コックピット計器 UI + サイズ契約。検証は [11](11-v2-alarmkit-setup.md) §6 |
| 週次レポート | ✅ `WeeklyReportView` + 純関数テスト |
| UI polish | ✅ `TrainTheme` / `TrainChrome` / 横向き compact（[12](12-ui-design.md)） |
| 切符・履歴の削除 | ✅ Hub はフルスワイプ。履歴はコンテキストメニュー + バナー Undo（[12](12-ui-design.md)） |
| 定時到着 / 定時運行 | ✅ 到着は完了として案内。定時・早着はいい結果の見出し。超過でも取り下げない |
| 車内放送 | ✅ `CheckInScheduling` + Focus 4 択 + 背面 LA alert（ロック中は沈黙） |
| 発券 App Intent | ✅ `IssueTicketIntent`。見積は Heuristic / 直前発行 |

## ディレクトリ（実装の地図）

```
Todo train/
  ContentView.swift        TabView（切符 / 履歴 / 設定）+ Focus cover
  App/                     AppModelContainer, CloudKitSync（`isConfigured` 既定 false）
  Core/
    Session/               SessionManager, TicketDeletion, DeletionUndo, CheckInScheduling, DeviceLock
    Alarms/                AlarmScheduling, EndBellDelivery, SessionEndSchedule
    Notifications/         OvertimeNotifier, CheckInNotifier
    History/               HistorySearch, TicketReissue, WeeklyReport, Punctuality, SessionTimeline
    Settings/              AppSettings
    Companion/             CompanionSyncRuntime, セルフィー配線（SYNC-3）
    Coaching/              CoachingEngine（Heuristic + OnDevice 1 行）
    Intents/               IssueTicketIntent
    Tickets/               TicketSortOrdering, TicketIssuer
  DesignSystem/            TrainTheme, TrainChrome, TrainLayout, TicketDeckLayout, EstimateChips,
                           DeleteConfirmation, EstimateSnapMapping, EstimateSnapGauge,
                           TicketIssueEject, TicketMotion, ArrivalInvalidateOverlay, PunctualityMomentOverlay,
                           MarsTicketSpec, MarsTicketView, TicketStackLayout
  Features/
    Hub/                   HubView, QuickAddBar（親指発券帯）, ServiceSummaryBar,
                           TicketStackView（peek。選択中はスロットの実券を隠す。未選択フルスワイプ。出入りは手前へ潜る）, HubMarsTicketCard,
                           HubStationChevronSign（提示レイヤ LED。Hiragino 量子化ドット）
    Focus/                 FocusView, FocusControlsView（車内放送 4 択含む）, OvertimeSheet
    Arrival/               PauseLimitSheet, TransferCanvasPresenter
    History/               HistoryView, HistoryCalendarStrip, HistoryDayPager, HistoryDayClockView, HistoryRideDetailView, WeeklyReportView
    LiveActivity/          LiveActivityManaging
    Reorder/               ReorderView
    Settings/              SettingsView
TodoTrainWidget/           Home Widget + Session LA + Alarm LA
TodoTrainCompanion/        macOS メニューバー accessory（SYNC-4。提案値）
Todo trainTests/           Swift Testing（CheckInScheduling / TicketIssuer 含む）
TodoTrainCompanionTests/   停車送信の純関数
Packages/TodoTrainSync/    同期芯（暗号・ペアリング・停車判定。UI なし）
sync/contract/             ワイヤ契約の正本
sync/worker/               Hono + Durable Object
sync/e2e/                  Linux 結合（client ↔ worker）
```

## 動作するユーザーフロー

1. 運行開始 → ツールバー `＋` で親指発券帯（Return / スナップ・ゲージで掃き出し）。Siri「切符を発行」でも可
2. 発車 → Focus（停車 / 到着 / 延長 / 超過 / 割り込み発券 / 車内放送）。到着したら短い案内。定時なら定時到着、早着なら早着
3. 長い乗務: 予測不能な車内放送。他アプリへ離れたとき: LA 割り込み「まだ乗ってる？」（ロック中は出さない）
4. 停車はいつでも。Live Activity は残り、StandBy などから再乗車できる。停車が満杯の新規発車 / 割り込みは整理シート
5. 履歴は週ストリップと時計キャンバスで振り返る（左右スワイプで日付、ピンチで 1/3/7 日。空き時間は折り畳まない）。ブロックを開いて乗り継ぎ・今日に追加（定時はバッジのみ）
6. 運行終了 → 停車中の持ち越し禁止 / 途中下車 / 放棄。遅延がなければ短い「定時運行」（早着可）
7. 終了ベル ON → AlarmKit LA（StandBy）/ OFF → Session LA。停車中も同じ経路の LA が残る

## 既知のギャップ（意図的）

| 項目 | 備考 |
|------|------|
| CloudKit | スキーマ準備済み。store は `.none`。**iCloud entitlement なし**。Mac 土管には使わない |
| Session LA からの Intent | 走行中の停車は `SessionPauseIntent`。停車中の再乗車は `SessionResumeIntent`。到着・延長は deep link |
| iPad 最適化 | v2 以降。iPhone アプリの自由リサイズ（ミラーリング）は Hub がシーン幅に追従 |
| 乗り継ぎキャンバスのゲージ統一 | Phase 2（Quick Add のみ線形スナップ・ゲージ） |
| Mac Companion | Linux 芯は完了（[13](13-sync-mac-companion.md) / [15](15-agent-work-plan.md)）。メニューバー吹き出しは SYNC-4。iOS 配線（SYNC-3）は Settings セルフィー + ScenePhase。体験は [14](14-mac-companion-ux.md)。実機確認は [16](16-wakeup-checklist.md) |

## テスト

- スキーム: `Todo train`（iOS）/ `TodoTrainCompanion`（macOS）
- ユニット: `Todo trainTests`、`TodoTrainCompanionTests`
- 同期パッケージ: `cd Packages/TodoTrainSync && ../../sync/linux-swift.sh test`
- 同期結合: `./sync/e2e/run.sh`（ローカル wrangler + Swift クライアント）
- Worker: `cd sync/worker && npm test`

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

## Mac 実機チェック（車内放送）

シミュレータでは通知・scenePhase・Foundation Models が弱い。

- [ ] 30 分切符: 放送が 1–2 回、時刻が毎回ズレる、予告がない
- [ ] 5–10 分: 進捗放送なし
- [ ] 放送中に超過しない／超過中に放送しない
- [ ] 他アプリへ退避（画面オン）→ 数十秒で Session LA バナー「まだ乗ってる？」→ 停車が効く。タップで Focus
- [ ] ロックして作業 → away 通知も LA alert も出ない
- [ ] 終了ベル ON → 同じ退避で away バナーが重ならない
- [ ] 放送 OFF で沈黙
- [ ] オンデバイス文面が出る／失敗時は固定文「まだ『…』？」
- [ ] 発行祝祭と Return 一発発券が壊れていない
- [ ] Siri / ショートカット「切符を発行」

## Personal Team でできるデバッグ

- [x] シミュレータ / Personal Team 実機でアプリ本体（CloudKit なし）
- [ ] 実 iCloud 同期 — **有料 Apple Developer Program が必要**。いま iCloud Capability を足すと署名が壊れる

