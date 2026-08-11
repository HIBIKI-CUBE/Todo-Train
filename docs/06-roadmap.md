# 06 — ロードマップと実装順

## フェーズ概要

| フェーズ | ゴール |
|----------|--------|
| **MVP** | 運行 + 掃き出し + 発車 + 停車/到着/延長 + 基本履歴 + タグ |
| **v0.5** | 臨時停車 UI、体験の磨き |
| **v1** | Live Activity（発車中）、Widget（運行状態）、PCC、並べ替えビュー、履歴検索・今日に追加、CloudKit |
| **v2** | AlarmKit + StandBy、週次レポート、iPad 等 |

## MVP に含む

- [x] / 進行中: `Ticket`, `WorkSession`, `ServiceDay`, `TaskLineage`, `Tag`
- [x] / 進行中: `SessionManager`（Date ベース、運行、停車上限）
- Hub: 切符 CRUD、発車、FAB 即キーボード、ドラッグ並べ替え
- **タグ UI**
- Focus: 停車 / 到着 / 延長 / 超過 3 択
- 停車上限解決シート
- 到着整理キャンバス（手動）
- 運行開始 / 終了 + 日付跨ぎプロンプト
- 基本履歴 + 乗り継ぎリンク
- Heuristic 見積もり提案
- ローカル超過通知

## MVP に含めない

| 機能 | 時期 |
|------|------|
| 履歴検索・今日に追加 | v1 |
| sticky 日次 stats 本格版 | v1 |
| 並べ替え専用ビュー | v1 |
| Live Activity | v1 |
| Widget | v1 |
| PCC / オンデバイス AI | v1 |
| CloudKit | v1 |
| 期限フィールド | v1 |
| 臨時停車 UI | v0.5 |
| AlarmKit / StandBy | v2 |
| JSON エクスポート | 不要 |

## 推奨実装順（計画時）

1. Enums + モデル + `Item` 削除
2. **SessionManager** + `SessionClock` + 単体テスト
3. 運行開始/終了 + 日付跨ぎ
4. Focus + 超過
5. Hub + Quick Add + タグ
6. 停車上限 + 到着整理キャンバス
7. 履歴 + Lineage リンク
8. Heuristic + 通知

> 切符デザインより SessionManager を先に — 複数レビューで一致。すでに `develop` でコアは着手済み。

## v0.5

- 臨時停車許可（セーフティカバー + スライド、制限なし、「今日 n 回目」）
- ArrivalDraft 中断復帰
- 停車メモ 1 行（任意）

## v1

- Live Activity（**発車中のみ**）: 残時間、停車/到着 Intent
- Widget: 運行中・未乗務表示
- PCC: 到着整理の分割提案、日次レビュー（ユーザー起動）
- 並べ替えビュー（全表示 + フィルタ強調）
- 履歴検索 + 今日に追加 + sticky stats
- CloudKit + デバイス間セッションロック
- 期限（任意・自動ソートなし）

## v2

- AlarmKit（終了ベル）+ StandBy 強化
- App Intents / Siri
- 週次レポート、系譜可視化、iPad

## 受入の芯（MVP）

| 領域 | 基準 |
|------|------|
| Session | 発車→経過→停車→再開→到着が Date ベースで正しい |
| 運行 | 運行なしで発車不可。終了時に停車中を乗り継ぎ/放棄 |
| Focus | dismiss 不可。延長で Hub に戻らない |
| 上限 | 停車 3 枚目は解決シート |
| 掃き出し | FAB から 2〜3 操作で切符追加 |
| Lineage | 途中下車→子切符にリンク |
