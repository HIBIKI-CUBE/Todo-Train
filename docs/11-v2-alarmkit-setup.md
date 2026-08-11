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
| Session Live Activity（v1） | 発車中の残時間表示（別 Attributes・未配線可） |
| AlarmKit 終了ベル（v2） | 見積もり到達の強制通知（Focus/Silent 突破） |
| Alarm Live Activity | StandBy / ロック画面のカウントダウン（`AlarmAttributes`） |

## 3. Widget Extension（現状）

`TodoTrainWidget` ターゲットがリポジトリに含まれています。

| ファイル | 役割 |
|----------|------|
| `TodoTrainWidgetBundle.swift` | `@main` — Alarm LA のみ束ねる |
| `TodoTrainAlarmLiveActivity.swift` | `AlarmAttributes<TodoTrainAlarmMetadata>` の UI（countdown / paused / alert） |
| `TodoTrainAlarmMetadata.swift` | App + Extension 共有（両方のターゲットでコンパイル） |
| `TodoTrainWidget.swift` | ホーム画面 Widget（**未接続**・後続） |

ホーム画面 Widget を足すときは `TodoTrainWidgetBundle` に追加し、ターゲット membership を更新してください。

## 4. 設定

Hub → 設定 → **終了ベル（AlarmKit）** を ON にすると、発車中セッションの予定終了時刻に AlarmKit タイマーがスケジュールされます。

- 停車 / 到着 / 途中下車 / 放棄 / 延長で再スケジュールまたはキャンセル
- AlarmKit 拒否時もセッションは `SessionManager` + DB が真実源

## 5. Mac 検証チェックリスト

- [ ] AlarmKit 権限プロンプト
- [ ] 発車 → StandBy / ロック画面 / Dynamic Island でカウントダウン
- [ ] 予定終了でベル（Silent 時も）
- [ ] 延長でタイマー更新
- [ ] 停車でキャンセル
- [ ] v1 Session Live Activity と競合しないこと（現状 Session LA Widget UI は未実装）

## 6. ブランチ

表示配線の作業ブランチ: `feature/alarmkit-display`
