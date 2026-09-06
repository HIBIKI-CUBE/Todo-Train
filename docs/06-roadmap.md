# 06 — ロードマップと実装順

## フェーズ概要

| フェーズ | ゴール | 状態 |
|----------|--------|------|
| **MVP** | 運行 + 掃き出し + 発車 + 停車/到着/延長 + 履歴 + タグ + 通知 + Override + Heuristic + 運行終了整理 | **完了**（Sprint 1–10） |
| **v0.5** | （臨時停車 UI 等） | MVP に吸収済み |
| **v1** | Settings、履歴検索・今日に追加、並べ替えビュー、dueDate、カスタム見積、LA、Widget、AI stub | **完了**（CloudKit を除く） |
| **v2** | AlarmKit + StandBy、週次レポート、UI polish、横向き compact | **完了**（iPad 等は未着手） |
| **定時** | 定時到着 / 定時運行の短い案内（非通貨） | **完了** |
| **車内放送** | 乗務中チェックイン + 背面「まだ乗ってる？」+ 発券 Intent | **完了** |
| **次** | E2E リレー + Mac 最小（走行中の停車） | 経路確定。[13](13-sync-mac-companion.md)。実装は次 PR |

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

## v1（完了）

| WP | 内容 | 状態 |
|----|------|------|
| A | Settings（停車上限 2/3、音） | ✅ |
| B | 履歴検索 + 今日に追加 | ✅ |
| C | 並べ替えビュー（全表示 + フィルタ強調） | ✅ |
| D | 期限 `dueDate`（任意・自動ソートなし） | ✅ |
| E | カスタム見積もり 1–60 | ✅ |
| F | Live Activity（**発車中のみ**） | ✅ |
| G | Home Widget（運行状態） | ✅ |
| H | AI / PCC（タップ起動・フォールバック必須） | stub 済 |
| I | CloudKit（独立 PR 推奨） | スキーマ準備のみ。Mac 土管には使わない（X-09）。ゲートは false のまま |

## v2（完了）

- [x] AlarmKit（終了ベル）+ StandBy LA
- [x] 週次レポート
- [x] ダークコックピット Focus / LA UI
- [x] iPhone 横向き compact レイアウト
- [x] App Intent「切符を発行」（Siri / ショートカット）。発車はしない
- [ ] 系譜可視化、iPad

## 車内放送（完了）

- [x] `CheckInScheduling` 純関数（10 分以下 0、11–25 分 1、30 分以上は 2。ジッター帯）
- [x] Focus 操作盤 4 択 + 背面 away 通知
- [x] 発車時オンデバイス 1 行（失敗時 Heuristic）
- [x] 設定トグル（既定 ON）

## 次軌道

1. **リレー** — Hono + Durable Object。暗号化スナップショットと停車コマンド。ポーリングなし。APNs なし
2. **iOS ペアリング** — QR、Keychain、前面 / `active` 復帰で送受信。`SessionManager` が停車を実行
3. **macOS 最小** — メニューバーで走行中タイトル・残り・停車。Hub のマルス体験は iPhone に残す
4. **WP-I CloudKit** — ゲート維持。Mac は待たない

## 受入の芯（MVP・達成済みの意図）

| 領域 | 基準 |
|------|------|
| Session | 発車→経過→停車→再開→到着が Date ベースで正しい |
| 運行 | 運行なしで発車不可。終了時に停車中を持ち越し/途中下車/放棄 |
| Focus | dismiss 不可。延長で Hub に戻らない |
| 上限 | 停車超過は解決シート。Override 可 |
| 掃き出し | FAB から少数操作で切符追加 |
| Lineage | 途中下車→子切符にリンク |
