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

## 主要モデル（実装済みの骨格）

| モデル | 役割 |
|--------|------|
| `Ticket` | 切符。見積もり上限 3600 秒。`closedAt` / `closureKind` |
| `WorkSession` | 1 回の乗車。pause 累積、予算秒、outcome |
| `ServiceDay` | 運行日。`calendarDayKey`（例: `2026-08-11`） |
| `TaskLineage` | 親→子の乗り継ぎ（continuation / split / discovered / manual） |
| `Tag` | タグ（名前・色・sortOrder） |

関連ルール（方針）:

- Tag↔Ticket は多対多（`@Relationship` 明示）
- CloudKit は v1 まで無効（entitlement の container ID は空のまま触らない）
- enum は String raw で保存（マイグレーション耐性）

## SessionManager 責務

- 運行開始 / 終了
- 発車 / 停車 / 再開 / 延長 / 到着・途中下車・放棄
- 停車上限ゲート（`PauseLimitGuard`）
- 日付跨ぎ検知 → `needsServiceDayEndPrompt`
- force-quit 後の open session 復元・複数 open の修復
- `ScenePhase.active` 復帰時の `reconcile()`

### 運行ルール（コードと一致）

| ルール | `SessionError` |
|--------|----------------|
| 運行なしで発車 | `.noActiveService` |
| 昨日の運行が open | `.serviceDayNeedsEnd` |
| 走行中に運行終了 | `.cannotEndServiceWhileRunning` |
| 二重発車 | `.alreadyBoarding` |
| 停車上限 | `.pauseLimitReached` |

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
- フォーカス中に AI 自動起動しない

## Live Activity（v1）

**1 LA = 1 乗務（発車中）**。全日運行 LA は不可（8h 上限）。  
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

## テスト

- `SessionManagerTests` — Date 注入（`SessionClock`）
- `PauseLimitGuard` / Lineage / HistoryStats
- BG・通知は手動チェックリスト
