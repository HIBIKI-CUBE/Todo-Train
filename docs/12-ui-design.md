# 12 — UI / ビジュアル方針

機能優先で育った UI を、**Apple プラットフォームの道具**として整える。  
スコープ: 色・タイポ・レイアウト・インタラクション。コーチング UI やウィザードは増やさない。

## コンセプト

**HIG を骨格に、列車メタファはアクセント**

| 面 | 方針 |
|----|------|
| Hub / 履歴 / 設定 | 標準の `List` / `Form`（`.insetGrouped`）。システム背景・セマンティック色 |
| Focus | 車内乗務の没入。システム外観に依存しない cabin。タイマーが主役 |
| 超過 / 臨時停車 | 信号色は意味を持たせる（緑・琥珀・赤） |

道具であること（`01-vision.md`）を崩さない。カスタムカード乱立・グラデ背景・FAB 祭りはしない。

## ナビゲーション

| 要素 | 置き場所 |
|------|----------|
| 切符（Hub） / 履歴 / 設定 | **TabView**（下部タブ） |
| 切符追加 | Hub ツールバー `＋` → **シート**（`QuickAddSheet`） |
| タグ / 並べ替え | Hub の `…` メニュー、または設定内リンク |
| Focus | 発車時のフルスクリーンカバー（既存） |

上部ツールバーに主要導線を詰めない。

## カラー

| 役割 | 実装 | 使い方 |
|------|------|--------|
| **Ink / Muted** | `Color.primary` / `.secondary` | 本文・メタ（ダーク自動対応） |
| **Platform / Surface** | `systemGroupedBackground` 系 | List / Form のキャンバス |
| **Rail** | `AccentColor`（ライト紺 / ダークは明るめ） | CTA・タブ強調 |
| **Signal Green / Amber / Red** | adaptive UIColor | 到着・停車・超過 |
| **Cabin** | 固定ダーク | Focus のみ |

ハードコードした白カード・クリームグラデは使わない。

## タイポグラフィ

| 用途 | 指定 |
|------|------|
| 画面タイトル | システム `navigationTitle`（large / inline） |
| 切符タイトル | `.body` + semibold |
| タイマー | **超大・rounded + monospacedDigit**（Focus の主役） |
| メタ | `.caption`、`.secondary` |
| 運行ステータス | `.subheadline` + semibold |

装飾用セリフや新聞調は使わない。

## レイアウトとコントロール

- Hub: `List` + 標準行。`TicketCardView` はリスト行（枠カードにしない）。
- 追加 UI: **シート + Form**。タイトル即フォーカス、見積もり・タグを同面、連続追加後もキーボード維持。
- ボタン: 可能な限り `.bordered` / `.borderedProminent` / `role: .destructive`。
- Focus: 縦一列。操作は下部。cabin 専用スタイルのみ例外。

## モーション（意図的に 2–3）

1. **発車**: Focus 出現はシステムフルスクリーン。内部タイマーは 1 秒 tick のみ。
2. **超過突入**: タイマー色を amber→red へ、軽いスケールパルス 1 回。
3. **シート**: システム presentation（detents medium/large）。過剰な spring は避ける。

ノイズになるパララックス・常時グローは禁止。

## やらないこと

- 紫グラデ / 汎用 SaaS ダーク / クリーム×テラコッタ×セリフ
- カスタム FAB・半透明オーバーレイのボトムバー追加 UI
- 絵文字アイコンの多用
- コーチング吹き出し
- Web / Flutter 風の独自カードグリッドを「ブランド」にする行為

## 実装マップ

| ファイル | 役割 |
|----------|------|
| `DesignSystem/TrainTheme.swift` | adaptive 色・余白・型 |
| `DesignSystem/TrainChrome.swift` | Focus cabin・SignalBadge・Focus ボタン |
| `ContentView.swift` | TabView + Focus cover |
| `Features/Hub/QuickAddBar.swift` | `QuickAddSheet` |
| 各 Feature | 標準 List / Form |
