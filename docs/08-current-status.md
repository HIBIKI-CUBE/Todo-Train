# 08 — 現状ステータス

最終更新: 2026-09-05（車内放送 + 発券 App Intent）

## 結論

**MVP（Sprint 1–10）・v1・v2（AlarmKit / UI polish）・車内放送は実装済み。**  
未着手の大きな塊は **CloudKit（WP-I）**。その後に Mac 最小面。実装マップと検証手順は本ファイルと [11-v2-alarmkit-setup.md](11-v2-alarmkit-setup.md) / [12-ui-design.md](12-ui-design.md) を参照。

定時の喜びは **エフェメラ**。到着は完了ジェスチャ（切符の無効化）で祝う。ストリークや定時率は出さない。超過で案内は取り下げない。

発行の単発祝祭はマルス 8.5cm 未使用券（[references/](references/)）。到着は同じ券面をスワイプで使用済みにする（`ArrivalInvalidateOverlay`）。

### v1 進捗

| WP | 状態 | 備考 |
|----|------|------|
| WP-A Settings | ✅ | 停車上限 2/3、超過音、充電中は消さない、車内放送 |
| WP-B History | ✅ | 検索 + 今日に追加 |
| WP-C Reorder | ✅ | フィルタ強調 + D&D |
| WP-D dueDate | ✅ | 任意期限、自動ソートなし |
| WP-E Custom estimate | ✅ | 1–60 分任意入力 |
| WP-F Live Activity | ✅ | Session LA + AlarmKit 排他。[11](11-v2-alarmkit-setup.md) §6 で検証 |
| WP-G Widget | ✅ | App Group スナップショット |
| WP-H AI / PCC | 部分 | 分割・日次レビューは stub。車内放送 1 行は `OnDeviceCoachingEngine` |
| WP-I CloudKit | 未着手 | 独立 PR 推奨。Mac 最小面の前提 |

### v2 進捗

| 項目 | 状態 |
|------|------|
| AlarmKit 終了ベル | ✅ `AlarmScheduling` + Settings トグル |
| StandBy / Session LA | ✅ コックピット計器 UI + サイズ契約。検証は [11](11-v2-alarmkit-setup.md) §6 |
| 週次レポート | ✅ `WeeklyReportView` + 純関数テスト |
| UI polish | ✅ `TrainTheme` / `TrainChrome` / 横向き compact（[12](12-ui-design.md)） |
| 切符・履歴の削除 | ✅ フルスワイプ + バナー Undo（[12](12-ui-design.md)） |
| 定時到着 / 定時運行 | ✅ 到着は完了として案内。定時・早着はいい結果の見出し。超過でも取り下げない |
| 車内放送 | ✅ `CheckInScheduling` + Focus 4 択 + 背面通知。設定トグル |
| 発券 App Intent | ✅ `IssueTicketIntent`。見積は Heuristic / 直前発行 |

## ディレクトリ（実装の地図）

```
Todo train/
  ContentView.swift        TabView（切符 / 履歴 / 設定）+ Focus cover
  Core/
    Session/               SessionManager, TicketDeletion, DeletionUndo, CheckInScheduling
    Alarms/                AlarmScheduling, EndBellDelivery, SessionEndSchedule
    Notifications/         OvertimeNotifier, CheckInNotifier
    History/               HistorySearch, TicketReissue, WeeklyReport, Punctuality
    Settings/              AppSettings
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
    History/               HistoryView, WeeklyReportView
    LiveActivity/          LiveActivityManaging
    Reorder/               ReorderView
    Settings/              SettingsView
TodoTrainWidget/           Home Widget + Session LA + Alarm LA
Todo trainTests/           Swift Testing（CheckInScheduling / TicketIssuer 含む）
```

## 動作するユーザーフロー

1. 運行開始 → ツールバー `＋` で親指発券帯（Return / スナップ・ゲージで掃き出し）。Siri「切符を発行」でも可
2. 発車 → Focus（停車 / 到着 / 延長 / 超過 / 割り込み発券 / 車内放送）。到着したら短い案内。定時なら定時到着、早着なら早着
3. 長い乗務: 予測不能な車内放送。ホーム退避: 「まだ乗ってる？」
4. 停車上限 → 解決シート / 途中下車キャンバス / 臨時停車
5. 履歴で振り返り・乗り継ぎリンク・今日に追加（定時はバッジのみ）
6. 運行終了 → 停車中の持ち越し禁止 / 途中下車 / 放棄。遅延がなければ短い「定時運行」（早着可）
7. 終了ベル ON → AlarmKit LA（StandBy）/ OFF → Session LA

## 既知のギャップ（意図的）

| 項目 | 備考 |
|------|------|
| CloudKit | entitlement あり・未使用 |
| Session LA からの Intent | 未実装（Alarm LA は `EndBellIntents` 済み） |
| iPad 最適化 | v2 以降。iPhone アプリの自由リサイズ（ミラーリング）は Hub がシーン幅に追従 |
| 乗り継ぎキャンバスのゲージ統一 | Phase 2（Quick Add のみ線形スナップ・ゲージ） |
| Mac Companion | CloudKit 後。メニューバーで走行中・停車。今回は未着手 |

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

## Mac 実機チェック（車内放送）

シミュレータでは通知・scenePhase・Foundation Models が弱い。

- [ ] 30 分切符: 放送が 1–2 回、時刻が毎回ズレる、予告がない
- [ ] 5–10 分: 進捗放送なし
- [ ] 放送中に超過しない／超過中に放送しない
- [ ] ホームへ退避 → 数十秒で「まだ乗ってる？」→ 停車が効く
- [ ] 放送 OFF で沈黙
- [ ] オンデバイス文面が出る／失敗時は固定文「まだ『…』？」
- [ ] 発行祝祭と Return 一発発券が壊れていない
- [ ] Siri / ショートカット「切符を発行」
