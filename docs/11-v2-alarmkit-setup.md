# v2 — AlarmKit / StandBy セットアップ

v1 PR（#2）が Mac 検証前でも、AlarmKit 連携のコード境界はこのリポジトリに置いてあります。**実機/シミュレータでの動作確認は必須**です。

## 1. Info.plist

メインターゲット `Todo train/Info.plist` に追加済み:

- `NSAlarmKitUsageDescription` — 終了ベルの用途説明

## 2. 役割分離（`07-research.md`）

| 層 | 役割 |
|----|------|
| Session Live Activity（v1） | 発車中の残時間表示 |
| AlarmKit 終了ベル（v2） | 見積もり到達の強制通知（Focus/Silent 突破） |
| Alarm Live Activity | StandBy / ロック画面のカウントダウン（AlarmAttributes） |

## 3. Widget Extension

1. Xcode で Widget Extension を作成（未作成なら `TodoTrainWidget/README.md` 参照）
2. `TodoTrainAlarmLiveActivity.swift` を Extension ターゲットに追加
3. `@main` が複数になる場合は、Widget Bundle で `TodoTrainWidget` + `TodoTrainAlarmLiveActivity` を束ねる

## 4. 設定

Hub → 設定 → **終了ベル（AlarmKit）** を ON にすると、発車中セッションの予定終了時刻に AlarmKit タイマーがスケジュールされます。

- 停車 / 到着 / 途中下車 / 放棄 / 延長で再スケジュールまたはキャンセル
- AlarmKit 拒否時もセッションは `SessionManager` + DB が真実源

## 5. Mac 検証チェックリスト

- [ ] AlarmKit 権限プロンプト
- [ ] 発車 → StandBy / ロック画面でカウントダウン
- [ ] 予定終了でベル（Silent 時も）
- [ ] 延長でタイマー更新
- [ ] 停車でキャンセル
- [ ] v1 Live Activity と競合しないこと

## 6. v1 未検証について

v1 の SessionManager / LA 配線が Mac で問題ないことを先に確認してから、AlarmKit の細部（表示文言・Intent）を詰めることを推奨します。
