# 06 — ロードマップと実装順

## フェーズ概要

| フェーズ | ゴール | 状態 |
|----------|--------|------|
| **MVP** | 運行 + 掃き出し + 発車 + 停車/到着/延長 + 履歴 + タグ + 通知 + Override + Heuristic + 運行終了整理 | **完了**（Sprint 1–10） |
| **v0.5** | （臨時停車 UI 等） | MVP に吸収済み |
| **v1** | Settings、履歴検索・今日に追加、並べ替えビュー、dueDate、カスタム見積、LA、Widget、AI stub、CloudKit | **次** → [09-v1-implementation.md](09-v1-implementation.md) |
| **v2** | AlarmKit + StandBy、週次レポート、iPad 等 | **実装中**（AlarmKit 境界 + 週次レポート） |

## MVP（完了チェック）

- [x] `Ticket`, `WorkSession`, `ServiceDay`, `TaskLineage`, `Tag`
- [x] `SessionManager`（Date ベース、運行、停車上限）
- [x] Hub: 切符、発車、FAB、ドラッグ並べ替え
- [x] タグ UI
- [x] Focus: 停車 / 到着 / 延長 / 超過 3 択
- [x] 停車上限解決シート + 臨時停車
- [x] 途中下車キャンバス（手動）
- [x] 運行開始 / 終了 + 日付跨ぎ + 終了時停車整理
- [x] 基本履歴 + sticky 日ヘッダ + 乗り継ぎリンク
- [x] Heuristic 見積もり提案
- [x] ローカル超過通知

詳細マップ: [08-current-status.md](08-current-status.md)

## v1（実装指示は 09）

| WP | 内容 |
|----|------|
| A | Settings（停車上限 2/3、音） |
| B | 履歴検索 + 今日に追加 |
| C | 並べ替えビュー（全表示 + フィルタ強調） |
| D | 期限 `dueDate`（任意・自動ソートなし） |
| E | カスタム見積もり 1–60 |
| F | Live Activity（**発車中のみ**） |
| G | Home Widget（運行状態） |
| H | AI / PCC（タップ起動・フォールバック必須） |
| I | CloudKit（独立 PR 推奨） |

含めない: AlarmKit、全日 LA、コーチングウィザード、JSON エクスポート。

## v2

- AlarmKit（終了ベル）+ StandBy 強化
- App Intents / Siri 拡充
- 週次レポート、系譜可視化、iPad

## 受入の芯（MVP・達成済みの意図）

| 領域 | 基準 |
|------|------|
| Session | 発車→経過→停車→再開→到着が Date ベースで正しい |
| 運行 | 運行なしで発車不可。終了時に停車中を持ち越し/途中下車/放棄 |
| Focus | dismiss 不可。延長で Hub に戻らない |
| 上限 | 停車超過は解決シート。Override 可 |
| 掃き出し | FAB から少数操作で切符追加 |
| Lineage | 途中下車→子切符にリンク |
