# 12 — UI / ビジュアル方針

機能優先で育った UI を、**Apple プラットフォームの道具**として整える。  
スコープ: 色・タイポ・レイアウト・インタラクション。コーチング UI やウィザードは増やさない。

## コンセプト

**HIG を骨格に、列車メタファはアクセント**

| 面 | 方針 |
|----|------|
| Hub / 履歴 / 設定 | 標準の `List` / `Form`（`.insetGrouped`）。システム背景・セマンティック色 |
| Focus | 真っ黒ダッシュボード。超大タイマーが主役。hairline パネル格子＋ gapless 操作盤 |
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
| **Cabin** | 純黒（状態時のみ薄い wash） | Focus のみ |

ハードコードした白カード・クリームグラデは使わない。

## タイポグラフィ

| 用途 | 指定 |
|------|------|
| 画面タイトル | システム `navigationTitle`（large / inline） |
| 切符タイトル | `.body` + semibold |
| タイマー | **画面大半を占める超大・rounded + monospacedDigit**（Geometry 追従） |
| 進捗バー | テレメトリ帯。経過は塗りのみ。下段に予定時刻＋見積もりメタ |
| 状態語 | ヘッダ右に非平常時のみ（`終盤` / `まもなく` / `超過`）。色は予算比で段階変化（固定1分ルールではない） |
| メタ | `.caption`、`.secondary` |
| 運行ステータス | `.subheadline` + semibold |

装飾用セリフや新聞調は使わない。

## レイアウトとコントロール

- Hub: `List` + 標準行。`TicketCardView` はリスト行（枠カードにしない）。
- 追加 UI: **シート + Form**。タイトル即フォーカス、見積もり・タグを同面、連続追加後もキーボード維持。
- ボタン: 可能な限り `.bordered` / `.borderedProminent` / `role: .destructive`。
- Focus: エッジツーエッジのパネル格子（ヘッダ／タイマー／テレメトリ／操作）。丸角カードや大きな余白は使わない。

## 横向き（iPhone compact height）

トリガー: `verticalSizeClass == .compact`（`EnvironmentValues.isCompactHeight`）。iPad 分割ビューは v2 スコープ外。

| 原則 | 内容 |
|------|------|
| 高さは希少 | large title を inline に、サマリー・ヘッダを 1 行化 |
| 幅は密度 | 行内メタ・タグを横展開。空き幅のダッシュボード化はしない |
| Hub 2 ペイン | compact 時は左 280pt に運行＋停車、右に切符リスト（単一 List の横伸びはしない） |
| 骨格維持 | List / Form / cabin。マスター・ディテール分割・FAB は増やさない |
| Focus 例外 | portrait は縦パネル格子。compact は計器 \| 操作の 2 ペイン（幅約 38%） |

実装: `DesignSystem/TrainLayout.swift`。

## AlarmKit / StandBy（終了ベル LA）

Focus ダッシュボードの **ダーク計器エコー**。Lock Screen / StandBy は Alarm LA（終了ベル ON）または Session LA（OFF）で同一の視覚言語。

| 面 | 方針 |
|----|------|
| 背景 | 純黒 tint（旧 Accent 薄カードは廃止） |
| 計器 | ヘッダ（タイトル + 状態語）・大タイマー・消費進捗バー・予定時刻 |
| 段階色 | `FocusTimerPhase`（予算比 25% / 10%）。固定1分ルールではない |
| 状態語 | 平常は非表示。終盤 / まもなく / 超過 / 停車中 |
| 操作（Alarm LA） | gapless 2 列（キャンセル \| 停車/再乗車/Stop）。`LiveActivityIntent` |
| compact DI | 相色ドット + 円形 Progress（長い timer テキスト禁止） |
| やらない | フルスクリーン没入・格子操作盤・到着 Intent・グラデ |

共有: `TodoTrainWidget/FocusTimerPhase.swift`, `CockpitInstrumentViews.swift`。

詳細手順は [11-v2-alarmkit-setup.md](11-v2-alarmkit-setup.md)。

## モーション（意図的に 2–3）

1. **発車**: Focus 出現はシステムフルスクリーン。内部タイマーは 1 秒 tick のみ。
2. **超過突入**: タイマー色を amber→red へ、軽いスケールパルス 1 回。全面ディムは使わず操作盤を超過 3 択に差し替え。
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
| `DesignSystem/TrainChrome.swift` | Focus 純黒ダッシュボード・進捗バー・計器バンク・SignalBadge |
| `TodoTrainWidget/FocusTimerPhase.swift` | App + Widget 共有の段階色ロジック |
| `TodoTrainWidget/CockpitInstrumentViews.swift` | StandBy / LS 用ダーク計器部品 |
| `ContentView.swift` | TabView + Focus cover |
| `Features/Hub/QuickAddBar.swift` | `QuickAddSheet` |
| 各 Feature | 標準 List / Form |
