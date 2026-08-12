# 12 — UI / ビジュアル方針

機能優先で育った UI を、**Apple プラットフォームの道具**として整える。  
スコープ: 色・タイポ・レイアウト・インタラクション。コーチング UI やウィザードは増やさない。

## コンセプト

**HIG を骨格に、列車メタファはアクセント**

| 面 | 方針 |
|----|------|
| Hub / 履歴 / 設定 | 標準の `List` / `Form`（`.insetGrouped`）。システム背景・セマンティック色 |
| Quick Add | システム sheet + **親指発券帯**（タイトル・常時タグ・KB 直上ゲージ）。Form / Disclosure ではない |
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
- 追加 UI: **親指発券帯**（`QuickAddSheet`）。タイトル即フォーカス、Return＝主発行、タグ横チップ常時、KB 直上に線形スナップ・ゲージ＋巨大数字。連続追加後もキーボード維持。
- ボタン: 可能な限り `.bordered` / `.borderedProminent` / `role: .destructive`（発券の主経路は Return／ゲージ）。タグチップ・ゲージノブは Liquid Glass。
- Focus: エッジツーエッジのパネル格子（ヘッダ／タイマー／テレメトリ／操作）。丸角カードや大きな余白は使わない。

### 破壊的操作（物理削除）

Undo があるので、[HIG Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) どおり **よくある削除に Alert は出さない**。

| 原則 | 内容 |
|------|------|
| フルスワイプ可 | 削除は即反映。`Label("削除", systemImage: "trash")` + `role: .destructive` |
| Undo | 下部バナー「取り消す」（約 8 秒）。スナップショット復元（UndoManager は使わない＝タイトル編集と混ざらない） |
| Alert なし | スワイプも詳細の削除ボタンも即削除＋バナー |
| `role: .destructive` | 本当に消える操作だけ（期限クリアには使わない） |

実装: `DeletionUndo` / `DeletionUndoCenter` / `DeleteConfirmation.swift`。

### 親指発券契約

| 軌道 | 操作 | 狙い直し |
|------|------|----------|
| 主 | タイトル → Return | 0 |
| 副 | ゲージ tap / scrub+release | 1（KB→直上） |
| 閉じる | 下スワイプ | — |

- 見積もり・タグ・挿入は sticky。タグ自動選択なし（無タグ発行可）
- 発行は即コミット + 短時間 Undo。確認ダイアログなし
- ゲージ: 指 X と塗りは分比例で一致。各停泊に sticky。**タイトル入力済みで発行するスクラブ中は detent を抑え**、祝祭はシート側の切符演出に一本化
- 挿入: ゲージ長押し。任意分: 巨大数字の長押し
- 発行フィードバック: **単発（デフォルト）**はコミット即 haptic＋Hub 切符（シート閉じと並列）。祝祭は短尺 ~0.55s（可読ホールド→着地）。**連続掃き出しトグル ON** は速度優先（selection haptic ＋ Undo のみ、切符演出なし）。Return / ゲージは同一経路
- 連続トグルはシート dismiss で OFF に戻る

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

Focus ダッシュボードの **ダーク計器エコー**。Lock Screen / StandBy は Alarm LA（終了ベル ON）または Session LA（OFF）で同一の視覚言語。HIG に沿い **残時間が主役・操作は原則 1 つ**。

| 面 | 方針 |
|----|------|
| 背景 | LS: `showsWidgetContainerBackground == true` のときだけ `Color.black`。StandBy: **箱型黒オーバーレイ禁止** — `.activityBackgroundTint(.black)` に端塗りを任せる（WWDC26） |
| StandBy 判定 | `EnvironmentValues.isActivityFullscreen`（レイアウト分岐）。背景の出し分けは `showsWidgetContainerBackground` |
| 情報階層 | **残時間 → 状態語 → タイトル / 予定**。小さい文字は補助のみ |
| 段階色 | `FocusTimerPhase`（予算比 25% / 10%）。固定1分ルールではない |
| 状態語 | 平常は非表示。終盤 / まもなく / 超過 / 更新待ち（stale） |
| StandBy 操作 | Alarm LA のみ **右ペイン縦計器セル**（停車 / 停止）。2×2 操作盤は廃止 |
| Lock Screen 操作 | Alarm LA のみ inset Capsule 1 つ。余白 **14pt**（compact 時は 8pt）。Session LA は表示専用 |
| StandBy レイアウト | **横長 2 ペイン**（左〜68% 計器 / 右〜32% 操作）。固定クロム（margin / タイトル / 進捗 / 予定）＋**タイマーが残り高を充填**。比率マジック禁止。120pt 未満はタイトル・予定を省略 |
| サイズ契約 | `CockpitLayoutContract`。LS/expanded DI は 408×84…160。StandBy は提案高をクランプせず、固定クロム＋残り高充填 |
| compact DI | tram マーク + **`Text(timerInterval:)` 秒更新**。幅は hidden 最大桁テンプレ（`0:00` / `00:00` / `0:00:00`）で決定。HIG 片側 **≤62.33pt** |
| minimal DI | **動的な残時間**（静的ドットのみにしない）。幅 ≤45pt |
| expanded DI | center にタイマー + タイトル。trailing は状態語のみ。Alarm 時のみ bottom 単一操作（≤40pt） |
| 鳴動アラート | システム描画。`tintColor` は amber（黒不可）。タイトルは切符名 |
| Deep link | `todotrain://focus`。到着・延長はアプリ内 Focus |
| やらない | Clock 級フルスクリーン・4 分割操作盤・停車中 LA の残留・途中下車ボタン・compact の静的ラベルだけ化・StandBy 比率チューニング競争 |

### ライフサイクル（表示と同期）

- **走行中 1 件だけ**が Alarm / LA を持つ。停車時は AlarmKit を `cancel`（`pause` で残さない）
- 再乗車はアプリから残時間で再 schedule
- 終了ベル ON かつ認可済 → AlarmKit が終了通知を独占（ローカル通知・アプリ超過音と重ねない）

### StandBy Preview ↔ 実機

StandBy は全画面 API ではなく、提案された帯をシステムが拡大する。入力は実測の提案サイズを使う（狭い帯の再現用に 408×84/120/160、大きい帯の再現用に **408×240 / 408×400**）。`max(h, 160)` で内部だけ高くしない。黒箱オーバーレイで帯を小さく見せない。

### StandBy「画面いっぱい」について

**不可能（同一レベル）**: Apple Clock/Timer のようなシステム専用没入 UI。ActivityKit は提案ビューをスケールし、背景 tint を延長するだけ。

**可能な上限**: `activityBackgroundTint` の端塗り + **固定クロムのあと残り高をタイマーが吸収**する横長 2 ペイン + 単一操作（現行）。

共有: `TodoTrainWidget/FocusTimerPhase.swift`, `CockpitLayoutContract.swift`, `CockpitInstrumentViews.swift`, `FocusPendingAction.swift`, `EndBellDelivery.swift`。

詳細手順・段階ゲートは [11-v2-alarmkit-setup.md](11-v2-alarmkit-setup.md) §6。


## モーション（意図的に 2–3）

1. **発車**: Focus 出現はシステムフルスクリーン。内部タイマーは 1 秒 tick のみ。
2. **超過突入**: タイマー色を amber→red へ、軽いスケールパルス 1 回。全面ディムは使わず操作盤を超過 3 択に差し替え。
3. **切符発行 / ゲージ**: 単発はコミット即祝祭（`Motion.issueEject` 短尺）＋シート閉じ並列。連続は褒め最小（haptic ＋ Undo）。発行時はゲージ detent と喧嘩させない。スクラブのみ（未入力）の停泊越えは impact＋`Motion.gaugeSnap`。

シート presentation はシステム detents。過剰な spring は避ける。

ノイズになるパララックス・常時グローは禁止。

## やらないこと

- 紫グラデ / 汎用 SaaS ダーク / クリーム×テラコッタ×セリフ
- カスタム FAB・Hub 上の半透明オーバーレイ・ボトムバー追加 UI（発券シート内の KB 直上親指帯・削除 Undo バナーは可）
- 絵文字アイコンの多用
- コーチング吹き出し
- Web / Flutter 風の独自カードグリッドを「ブランド」にする行為
- フルスワイプと Alert の二重確認、同一 View への `.alert` 重ね

## 実装マップ

| ファイル | 役割 |
|----------|------|
| `DesignSystem/TrainTheme.swift` | adaptive 色・余白・型・`Motion.issueEject` / `gaugeSnap` |
| `DesignSystem/TrainChrome.swift` | Focus 純黒ダッシュボード・進捗バー・計器バンク・SignalBadge |
| `DesignSystem/DeleteConfirmation.swift` | フルスワイプ削除 + Undo バナー |
| `DesignSystem/EstimateSnapMapping.swift` | 見積もり分↔線形位置の純関数・sticky デテント |
| `DesignSystem/EstimateSnapGauge.swift` | KB 直上の線形スナップ・ゲージ |
| `DesignSystem/TicketIssueEject.swift` | 単発発行の Hub 切符着地 |
| `TodoTrainWidget/FocusTimerPhase.swift` | App + Widget 共有の段階色ロジック |
| `TodoTrainWidget/CockpitLayoutContract.swift` | Live Activity 公称サイズ契約・密度選択 |
| `TodoTrainWidget/CockpitInstrumentViews.swift` | StandBy 2ペイン / LS ViewThatFits ダーク計器 |
| `ContentView.swift` | TabView + Focus cover |
| `Features/Hub/QuickAddBar.swift` | `QuickAddSheet`（親指発券帯） |
| 各 Feature | 標準 List / Form |
