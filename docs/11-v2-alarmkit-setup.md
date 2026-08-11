# v2 — AlarmKit / StandBy セットアップ

AlarmKit 終了ベルと StandBy / ロック画面カウントダウン用 Live Activity の配線手順。**実機/シミュレータでの動作確認は必須**です。

## 1. Info.plist / Capability

メインターゲット:

- `Todo train/Info.plist` — `NSAlarmKitUsageDescription`
- Build Setting — `INFOPLIST_KEY_NSSupportsLiveActivities = YES`

Widget Extension（`TodoTrainWidget`）:

- `TodoTrainWidget/Info.plist` — `NSExtensionPointIdentifier = com.apple.widgetkit-extension` + `NSSupportsLiveActivities`
- ターゲットは Xcode プロジェクトに **作成済み**（Embed Foundation Extensions 済み）

## 2. 役割分離（`07-research.md`）

| 層 | 役割 |
|----|------|
| Session Live Activity（v1） | 発車中の残時間（終了ベル OFF 時。ON 時は出さない） |
| AlarmKit 終了ベル（v2） | 見積もり到達の強制通知（Focus/Silent 突破） |
| Alarm Live Activity | StandBy / ロック画面のカウントダウン + 停車/再乗車（`AlarmAttributes`） |

## 3. Widget Extension（現状）

`TodoTrainWidget` ターゲットがリポジトリに含まれています。

| ファイル | 役割 |
|----------|------|
| `TodoTrainWidgetBundle.swift` | `@main` — Home + Session LA + Alarm LA |
| `TodoTrainSessionLiveActivity.swift` | 発車中 Session LA |
| `TodoTrainAlarmLiveActivity.swift` | 大タイマー + Intent 操作ボタン + 細い compact |
| `TodoTrainActivityAttributes.swift` | App + Extension 共有（Session LA） |
| `WidgetSnapshot.swift` | App Group スナップショット |
| `EndBellIntents.swift` | App + Extension 共有（停車 / 再乗車 / キャンセル / Stop） |
| `TodoTrainAlarmMetadata.swift` | App + Extension 共有（`sessionID` + `ticketTitle`） |
| `Assets.xcassets/AccentColor` | rail tint（App と同色） |
| `TodoTrainWidget.swift` | ホーム画面 Widget（App Group 読取） |

## 4. 操作（カスタム LA + AlarmPresentation）

**重要:** `AlarmPresentation` の `pauseButton` / `resumeButton` は **システムテンプレート UI（フォールバック）用**です。カスタム `ActivityConfiguration` を出しているときは、**LA 内に `Button(intent:)` を自分で置く**必要があります（WWDC25）。

| 状態 | LA ボタン（Intent） | セッション同期 |
|------|---------------------|----------------|
| Countdown | **停車** `EndBellPauseIntent` / **キャンセル** `EndBellCancelIntent` | pause → `pauseFromAlarmKit` / cancel → `suppressEndBell` |
| Paused | **再乗車** `EndBellResumeIntent` / キャンセル | resume → `resumeFromAlarmKit` |
| Alert | システム Stop + `EndBellStopIntent` | 到着は自動にしない |

Intent は `TodoTrainWidget/EndBellIntents.swift`（App + Extension 共有）。

Focus からの停車は AlarmKit を **cancel せず pause**。再乗車は `resume`、失敗時のみ再 schedule。

停車上限到達時に StandBy から停車した場合は **臨時停車**として記録し、Alarm と DB を揃える（分裂させない）。

`AlarmKitScheduler.bind(sessionManager:)` が `alarmUpdates` を購読し双方向同期します。ユーザーがキャンセルしたベルは `suppressEndBell` で記憶し、前景復帰で復活させません（延長時は再 schedule）。

## 5. 設定

Hub → 設定 → **終了ベル（AlarmKit）** を ON にすると、発車中セッションの予定終了時刻に AlarmKit タイマーがスケジュールされます。

- 停車 → pause / 再乗車 → resume / 到着・途中下車・放棄 → cancel
- キャンセル（StandBy）→ suppress（走行継続、ベルなし）
- 延長 → 再 schedule（suppress 解除）
- AlarmKit 拒否時もセッションは `SessionManager` + DB が真実源

## 6. Mac 検証チェックリスト

- [ ] AlarmKit 権限プロンプト
- [ ] 発車 → StandBy / LS で大タイマー + 横 Progress + **停車/キャンセル操作**
- [ ] Dynamic Island compact が狭い（円 Progress のみ）
- [ ] StandBy で **停車** / **再乗車** がタップできる
- [ ] StandBy 停車 → アプリ側セッションが停車中；再乗車で復帰
- [ ] 停車上限満杯 + StandBy 停車 → 臨時停車として整合（Alarm/DB 分裂なし）
- [ ] StandBy キャンセル → 前景復帰でもベルが復活しない
- [ ] Focus 停車でも Alarm が消えず pause される
- [ ] 予定終了でベル；Stop で止まる（到着自動なし）
- [ ] 到着 / 放棄で Alarm が消える
- [ ] v1 Session Live Activity と競合しないこと（終了ベル ON 時は Session LA を出さない）

## 7. ブランチ

`feature/alarmkit-display`
