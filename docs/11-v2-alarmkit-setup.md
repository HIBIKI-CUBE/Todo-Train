# v2 — AlarmKit / StandBy セットアップ

AlarmKit 終了ベルと StandBy / ロック画面カウントダウン用 Live Activity の配線手順。**実機/シミュレータでの動作確認は必須**です。

## 1. Info.plist / Capability

メインターゲット:

- `Todo train/Info.plist` — `NSAlarmKitUsageDescription` + URL scheme `todotrain://`（LA タップ → Focus）
- Build Setting — `INFOPLIST_KEY_NSSupportsLiveActivities = YES`

Widget Extension（`TodoTrainWidget`）:

- `TodoTrainWidget/Info.plist` — `NSExtensionPointIdentifier = com.apple.widgetkit-extension` + `NSSupportsLiveActivities`
- ターゲットは Xcode プロジェクトに **作成済み**（Embed Foundation Extensions 済み）

## 2. 役割分離（`07-research.md`）

| 層 | 役割 |
|----|------|
| Session Live Activity（v1） | 発車中の残時間（終了ベル OFF 時。ON 時は出さない）。**表示専用** |
| AlarmKit 終了ベル（v2） | 見積もり到達の強制通知（Focus/Silent 突破） |
| Alarm Live Activity | StandBy / ロック画面のカウントダウン + **単一操作**（停車 / 停止） |

**不変条件:** Alarm / Live Activity を持てるのは **現在走行中のセッション最大 1 件**。停車中に AlarmKit を `pause` で残さない（即 `cancel`）。

## 3. Widget Extension（現状）

`TodoTrainWidget` ターゲットがリポジトリに含まれています。

| ファイル | 役割 |
|----------|------|
| `TodoTrainWidgetBundle.swift` | `@main` — Home + Session LA + Alarm LA |
| `TodoTrainSessionLiveActivity.swift` | 発車中 Session LA（終了ベル OFF） |
| `TodoTrainAlarmLiveActivity.swift` | 大タイマー + ダーク計器 + 単一 Intent（StandBy / LS） |
| `FocusTimerPhase.swift` / `CockpitInstrumentViews.swift` | App + Widget 共有の段階色・計器・`CockpitDisplayModel` |
| `TodoTrainActivityAttributes.swift` | App + Extension 共有（Session LA） |
| `WidgetSnapshot.swift` | App Group スナップショット |
| `EndBellIntents.swift` | App + Extension 共有（停車 / キャンセル / Stop / 到着・延長は deep link 用に残置） |
| `TodoTrainAlarmMetadata.swift` | App + Extension 共有（`sessionID` + `ticketTitle`） |
| `TodoTrainWidget.swift` | ホーム画面 Widget（App Group 読取） |

## 4. 操作とライフサイクル

**重要:** `AlarmPresentation` の `pauseButton` / `resumeButton` は **システムテンプレート UI（フォールバック）用**です。カスタム `ActivityConfiguration` では **原則 1 つの `Button(intent:)`** のみ（HIG）。

| 状態 | LA ボタン（Intent） | セッション同期 |
|------|---------------------|----------------|
| Countdown | **停車** `EndBellPauseIntent` のみ | → `pauseFromAlarmKit` の直後に Alarm **cancel**（paused LA を残さない） |
| Alert | システム Stop + `EndBellStopIntent` | 到着は自動にしない。超過 3 択はアプリ内 |
| （タップ全体） | `todotrain://focus` | アプリを開き Focus を表示。到着・延長は Focus 内 |

Intent は `TodoTrainWidget/EndBellIntents.swift`（App + Extension 共有）。

### 停車 / 再乗車

- Focus または StandBy から停車 → AlarmKit を **即 cancel**（pause 保存しない）
- 残時間の真実源は `WorkSession` + `SessionManager`
- 再乗車は **アプリから**。残時間で **新規 schedule**（旧 Alarm の `resume` は使わない）
- 停車上限到達時に StandBy から停車した場合は **臨時停車**として記録し、Alarm と DB を揃える

### 終了通知の排他（`EndBellDelivery`）

| 条件 | 経路 |
|------|------|
| 終了ベル ON かつ AlarmKit 認可済 | **AlarmKit のみ**（ローカル超過通知・アプリ内超過音なし） |
| 終了ベル OFF、または AlarmKit 未認可 | ローカル Time Sensitive 通知 + 前景は Focus 超過 UI |
| 前景でのローカル通知 | バナーを出さない（`willPresent` → `[]`）。Focus 超過 UI を優先 |

`AlarmKitScheduler.bind(sessionManager:)` が `alarmUpdates` を購読。ユーザーがキャンセルしたベルは `suppressEndBell` で記憶し、前景復帰で復活させません（延長時は再 schedule）。起動 / reconcile 時は走行中以外の自アプリ Alarm を回収します。

## 5. 設定

Hub → 設定 → **終了ベル（AlarmKit）** を ON にすると、発車中セッションの予定終了時刻に AlarmKit タイマーがスケジュールされます。

- 停車 → **cancel** / 再乗車 → **再 schedule** / 到着・途中下車・放棄 → cancel
- キャンセル（StandBy dismiss）→ suppress（走行継続、ベルなし）
- 延長 → 再 schedule（suppress 解除）
- AlarmKit 拒否時もセッションは `SessionManager` + DB が真実源（ローカル通知フォールバック）

## 6. 検証ゲート（公称サイズ → Activity Preview → Simulator → 実機）

**不合格なら次の段階へ進まない。** StandBy 固有の最終確認だけが実機必須。

### 6.1 公称サイズ Preview（コード / Canvas）

HIG 公称寸法で部品を直接入力する（StandBy 入力も **未スケール** の Lock Screen サイズ）。

| 面 | 入力サイズ |
|----|------------|
| Lock Screen / StandBy / expanded DI | **408×84 / 120 / 160**（Pro Max）、**371×84 / 120 / 160**（Pro）。StandBy 大帯は **408×240 / 408×400** も確認 |
| DI compact 片側 | **62.33×36.67** |
| DI minimal | **36.67〜45×36.67** |

- [ ] `CockpitInstrumentViews` の LS / StandBy matrix Preview で Session（表示専用）と Alarm（単一操作）相当を目視
- [ ] 長い日本語タイトル・開始直後 / 終盤 / まもなく / alert / overtime / stale で見切れなし
- [ ] StandBy は **横長 2 ペイン**（左〜68% 大タイマー、右〜32% 縦計器セル）。縦積みや 4 分割操作盤に戻っていない
- [ ] StandBy Preview で上下の空きがタイマーに吸収され、黒箱オーバーレイで帯が小さく見えない
- [ ] `CockpitLayoutContractTests` が緑（固定クロム＋min timer ≤ 提案高、digit-shape → width template）
- [ ] StandBy の 2× Preview は見た目確認用。**レイアウト入力自体は常に 408 幅**
- [ ] StandBy 大帯 Preview（240 / 400pt）でタイマーが残り高を埋め、見切れしない
- [ ] compact DI Preview: `Text(timerInterval:)` 秒更新 + hidden `00:00` 系テンプレで tram に寄る（HIG ≤62.33pt）

### 6.2 ActivityKit 公式 `#Preview`

- [ ] Session / Alarm の `.content`（Lock Screen）を全 ContentState で再生・ループ
- [ ] View Style **Content (StandBy)** があれば Alarm / Session で 2 ペインを確認（無ければ 6.1）
- [ ] `.dynamicIsland(.compact / .minimal / .expanded)` を全 ContentState で確認
- [ ] Canvas で VStack / HStack / ボタン境界を選択し、親領域内に収まること
- [ ] 桁上がり・最短/最長タイトルで compact trailing がクリップしない（`isDynamicIslandLimitedInWidth`）
- [ ] compact は秒更新を維持し、幅は hidden 最大桁テンプレ（`frame(maxWidth:)` のみに頼らない）
- [ ] expanded bottom 操作が **総高 40pt 以内**（`minHeight + padding` 二重加算なし）
- [ ] expanded trailing は状態語のみ、タイトルは center 下にありセンサー行で切れない
- [ ] Dynamic Type variants / Accessibility Inspector Audit（実機前）

> Xcode Activity Preview の View Style に **Content (StandBy)** がある場合は、公式 Preview でも StandBy 分岐を確認する。無い／信頼できない場合のみ、6.1 のサイズ直入力 Preview を必須ゲートとする。`isActivityFullscreen` 自体は読み取り専用のまま。背景は LS=`showsWidgetContainerBackground`、StandBy=`activityBackgroundTint`（[WWDC26 #223](https://developer.apple.com/videos/play/wwdc2026/223/) / [HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities/)）。

### 6.3 Simulator

- [ ] 実際の Live Activity を開始し Lock Screen + Dynamic Island を確認
- [ ] 発車 → LS で黒背景・大タイマー・進捗・予定（Alarm 時は停車 1 ボタン）
- [ ] 複数切符を順に発車・停車しても LA が **走行中 1 件だけ**
- [ ] 停車した切符は LA から即消え、再乗車で Alarm が 1 件だけ再作成
- [ ] 終了ベル ON・前景期限到達: AlarmKit のみ（ローカル通知バナー・アプリ超過音が重ならない）
- [ ] 終了ベル OFF: Session LA 同系ダーク計器、前景は Focus 超過 UI
- [ ] LA タップ → `todotrain://focus`

### 6.4 実機のみ（StandBy / センサー / 認証）

Simulator 合格後に限定する。

- [ ] AlarmKit 権限プロンプト
- [ ] **鳴動アラートのタイトル・カウントダウンが読める**（`tintColor` が背景と同色でない。タイトルは切符名）
- [ ] StandBy が「箱の中の細い帯」ではなく **tint 端塗り＋帯内残り高充填** に見える（[WWDC26 #223](https://developer.apple.com/videos/play/wwdc2026/223/)）
- [ ] StandBy Night Mode 赤 tint / Always-On 低輝度（色以外でも状態識別できる）
- [ ] センサー余白・角丸でクリップしない
- [ ] Dynamic Island 通常表示: **秒更新あり**かつ tram に寄る（hidden 最大桁幅。空きピルが広がらない）
- [ ] Dynamic Island 拡大で tram / 状態語 / 停車ボタンが見切れない
- [ ] Lock Screen / DI 上の VoiceOver 順序
- [ ] ロック中の Intent 認証（停車 / 停止）
- [ ] StandBy 停車 → アプリ側セッションが停車中；Hub / Focus から再乗車
- [ ] 停車上限満杯 + StandBy 停車 → 臨時停車として整合
- [ ] StandBy キャンセル（dismiss）→ 前景復帰でもベルが復活しない
- [ ] 予定終了でベル；Stop で止まる（到着自動なし）
- [ ] 到着 / 放棄で Alarm が消える

## 7. ブランチ

`feature/alarmkit-display`
