# 04 — 技術アーキテクチャ

## スタック

| 層 | 選択 |
|----|------|
| UI | SwiftUI |
| 永続化 | SwiftData（MVP ローカル） |
| 状態 | `@Observable` `SessionManager` |
| タイマー | **Date ベース**（`SessionClock` 注入でテスト可能） |
| 最小 OS | iOS 27.0 |
| Bundle ID | `dev.hibiki-cube.Todo-train` |

## 真実源

```
WorkSession (endedAt == nil)  ← 走行/停車の真実
        ↕
SessionManager.reconcile()
        ↕
UI tick（1秒）は表示専用のみ
```

- `Timer` に経過時間の真実を置かない
- `Ticket` の「走行中」は open `WorkSession` から派生
- Live Activity を消しても運行/セッションは DB が本尊
- 定時判定は `Punctuality` の純関数（当初見積もり vs 実績）。到着の祝祭は完了が先。フィールドを足してスコア化しない
- 車内放送の発火も `reconcile()` が Date / 経過秒で見る。スコアにはしない

## 主要モデル（実装済みの骨格）

| モデル | 役割 |
|--------|------|
| `Ticket` | 切符。見積もり上限 3600 秒。`closedAt` / `closureKind` |
| `WorkSession` | 1 回の乗車。pause 累積、予算秒、outcome、延長・停車区間 |
| `SessionExtension` | 延長 1 回。`addedSeconds` / `createdAt` |
| `SessionPause` | 停車 1 区間。`startedAt` / `endedAt`（再開または終了で閉じる） |
| `ServiceDay` | 運行日。`calendarDayKey`（例: `2026-08-11`） |
| `TaskLineage` | 親→子の乗り継ぎ（continuation / split / discovered / manual） |
| `Tag` | タグ（名前・色・sortOrder） |

関連ルール（方針）:

- Tag↔Ticket は多対多（`@Relationship` 明示）
- CloudKit 私有同期は **ゲート付き**。`CloudKitSync.isConfigured == false` のあいだ store は `.none`（ローカル）。iCloud Capability は **有料 Apple Developer Program のあと** に足す。Personal Team に iCloud / CloudKit を付けると署名が失敗する
- モデルは CloudKit 契約に合わせた（`@Attribute(.unique)` なし、リレーションは optional / `= []`、保存属性にデフォルト）
- 走行のベル / LA / 車内放送は `WorkSession.boardedDeviceID` が自機のときだけ。`nil` は CloudKit 前のローカルデータとして自機扱い
- リモート変更は `NSPersistentStoreRemoteChange` → `reconcile()` + 自機副作用の張り直し。`recoverOnLaunch` は呼ばない（取消済み終了ベルを復活させるため）
- enum は String raw で保存（マイグレーション耐性）

## SessionManager 責務

- 運行開始 / 終了
- 発車 / 停車 / 再開 / 延長 / 到着・途中下車 / 放棄 / 割り込み発車（`switchBoard`。`phase` を `.paused` にしない）。停車は `SessionPause` 区間を残す
- 車内放送（`answerCheckIn` / `beginAwayWatch` / `endAwayWatch`）
- 停車上限ゲート（`PauseLimitGuard.canBoardNewRide`）— 停車は常に可。新規発車と割り込み発車だけ止める
- 日付跨ぎ検知 → `needsServiceDayEndPrompt`
- force-quit 後の open session 復元・複数 open の修復
- `ScenePhase.active` 復帰時の `reconcile()`
- CloudKit リモート変更時の `handleRemoteStoreChange()`（`isConfigured` のときだけ）

### 運行ルール（コードと一致）

| ルール | `SessionError` |
|--------|----------------|
| 運行なしで発車 | `.noActiveService` |
| 昨日の運行が open | `.serviceDayNeedsEnd` |
| 走行中に運行終了 | `.cannotEndServiceWhileRunning` |
| 二重発車 | `.alreadyBoarding` |
| 停車上限での新規発車 | `.pauseLimitReached` |

## バックグラウンド超過（MVP）

| 層 | 手段 |
|----|------|
| 主 | FG 復帰時 `phase == .overtime` → 超過 UI |
| 副 | `UNUserNotification`（Time Sensitive）を超過時刻にスケジュール |
| v1 | Live Activity（発車中） |
| v2 | AlarmKit（終了ベル） |

通知だけに依存しない。

## AI アーキテクチャ（段階導入）

```
CoachingEngine（プロトコル）
├─ HeuristicCoachingEngine     ← MVP（中央値など）
├─ OnDeviceCoachingEngine      ← v1（SystemLanguageModel）
└─ PCCCoachingEngine           ← v1（PrivateCloudComputeLanguageModel）
```

- PCC entitlement: `com.apple.developer.private-cloud-compute`（早めに申請）
- PCC はユーザー起動時のみ。注釈「Private Cloud で処理」必須
- フォーカス中に会話 AI を自動起動しない。車内放送 1 行は **発車時** にオンデバイスで用意してよい（失敗時は Heuristic）
- `reconcile()` が進捗放送の発火も見る。オフセットは当初見積もりの経過秒（停車中は進まない）

## Live Activity（v1）

**1 LA = 走行中 1 件、または直近の停車中 1 件（最大 2 時間）**。全日運行 LA は不可（8h 上限）。  
詳細は [07-research.md](07-research.md)。

## 推奨フォルダ構成（現行に近い）

```
Todo train/
├── App/
├── Core/Session/
├── Models/
├── Features/{Hub,Focus,Arrival,History,TicketDetail,...}
├── DesignSystem/
└── Services/   # 通知・Audio 等（必要に応じて）
```

## CloudKit とデバッグ（Personal Team）

| できる | できない |
|--------|----------|
| シミュレータ / Personal Team 実機でアプリ本体のデバッグ | 実 iCloud 同期 |
| ローカル SwiftData（`cloudKitDatabase: .none`） | CloudKit Console / 私有 DB の中身確認 |
| スキーマ準備・自機 ID の単体テスト | iCloud Capability を付けたままの Personal Team 署名 |

同期の土管は CloudKit ではない（X-09 / [13-sync-mac-companion.md](13-sync-mac-companion.md)）。Mac の画面は [14-mac-companion-ux.md](14-mac-companion-ux.md)。iCloud entitlement は足さない。`isConfigured` は false のまま。

## テスト

- `SessionManagerTests` — Date 注入（`SessionClock`）・自機/他機のベル抑制
- `PauseLimitGuard` / Lineage / HistoryStats / `CloudKitSyncTests`
- BG・通知・実同期は手動チェックリスト
