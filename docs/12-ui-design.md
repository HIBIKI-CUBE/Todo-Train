# 12 — UI / ビジュアル方針

機能優先で育った UI を、**Apple プラットフォームの道具**として整える。  
スコープ: 色・タイポ・レイアウト・インタラクション。コーチング UI やウィザードは増やさない。

## コンセプト

**HIG を骨格に、列車メタファはアクセント**

| 面 | 方針 |
|----|------|
| Hub | システム背景のうえ、未乗車は **マルス券 Wallet peek**（つまむ → 改札帯で発車 → 運転台）。運行・停車は標準ブロック |
| 履歴 / 設定 | 標準の `List` / `Form`（`.insetGrouped`）。システム背景・セマンティック色 |
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

- Hub: 未乗車は `TicketStackView`（マルス券の **Wallet peek**。平リスト化しない）。フル券面を重ね、手前は全面可視。タップで **同じ券をつまみ上げ**。**発車は券面下端の改札帯**（印刷の一部。HIG ピルや Focus 黒盤は足さない）。券面タップは詳細。**発券後はリストに留まり祝祭を見せる**。タブ／ナビは focus 中もレイアウト固定。発車は短い黒吸い込みのあと Focus へ。停車中はスタック外。並べ替えは `…` → `ReorderView`。削除はコンテキストメニュー。
- 追加 UI: **親指発券帯**（`QuickAddSheet`）。タイトル即フォーカス、Return＝主発行、タグ横チップ常時、KB 直上に線形スナップ・ゲージ＋巨大数字。連続追加後もキーボード維持。
- ボタン: 可能な限り `.bordered` / `.borderedProminent` / `role: .destructive`（発券の主経路は Return／ゲージ。Hub での発車は **券の改札帯**）。タグチップ・ゲージノブは Liquid Glass。
- Focus: エッジツーエッジのパネル格子（ヘッダ／タイマー／テレメトリ／操作）。丸角カードや大きな余白は使わない。

### 破壊的操作（物理削除）

Undo があるので、[HIG Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) どおり **よくある削除に Alert は出さない**。

| 原則 | 内容 |
|------|------|
| 即削除可 | Hub スタックはコンテキストメニュー、詳細は削除ボタン。いずれも即反映 + `role: .destructive` |
| Undo | 下部バナー「取り消す」（約 8 秒）。スナップショット復元（UndoManager は使わない＝タイトル編集と混ざらない） |
| Alert なし | コンテキストメニューも詳細の削除も即削除＋バナー |
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
- 発行フィードバック: **単発（デフォルト）**はコミット即 haptic＋Hub 上のマルス券排出（シート閉じと並列）。祝祭は読ませる尺（印字後 ~1.8s ホールド、合計 ~2.5–2.8s）。**連続掃き出しトグル ON** は速度優先（selection haptic ＋ Undo のみ、切符演出なし）。Return / ゲージは同一経路
- 連続トグルはシート dismiss で OFF に戻る

## 祝祭面の例外（発行 / 到着）

Focus / 設定は HIG 骨格のまま。Hub の未乗車リストはマルス券スタックでモチーフを日常面にも載せる。**発行と到着の祝祭**はさらに演出を前面に出す。

| 面 | 方針 |
|----|------|
| 発行（単発） | 未使用のマルス 8.5cm 乗車券。**画面下端（シートが閉じる辺）から** 90°CW でスライド排出 → 正立。空中クリップしない。印字済み。**下スワイプで早めにはけられる**。参照: [references/mars-joshaken.png](references/mars-joshaken.png) |
| 到着 | 同じ未使用券が手元に出る。**自分で検札印をドンと押す**（破りはしない＝放棄に見えるため）。定時・早着は印色 / haptic のみ。超過でも核は同じ |
| 定時運行 | 運行終了時のみ。小さな「定時運行」カプセル（~0.9s）。破るジェスチャは使わない |
| やらない | 西洋ミシン目・16pt 角丸トースト・左色帯・`tram.fill`・鮭色エド券レイアウト・JR ロゴ地紋の複製・¥・偽駅名・コンフェッティ・点数 |

実装: `MarsTicketSpec` / `MarsTicketView` / `TicketIssueEject` / `ArrivalInvalidateOverlay`。

## モーション（意図的に少ない）

1. **発車**: Focus 出現はシステムフルスクリーン。内部タイマーは 1 秒 tick のみ。
2. **超過突入**: タイマー色を amber→red へ、軽いスケールパルス 1 回。全面ディムは使わず操作盤を超過 3 択に差し替え。
3. **切符発行 / ゲージ**: 単発はコミット即マルス排出（シートから 90°CW → 正立、`MarsTicketSpec.IssueMotion` 固定 ms）＋シート閉じ並列。連続は褒め最小（haptic ＋ Undo）。発行時はゲージ detent と喧嘩させない。スクラブのみ（未入力）の停泊越えは impact＋`Motion.gaugeSnap`。
4. **到着**: Focus 閉鎖後に `ArrivalInvalidateOverlay`。検札印ハンドルが券の上で誘い、ユーザーが押す／タップするまで待つ。破りは使わない。定時・早着は印 / haptic の味付け。超過でも取り下げない。点数・コンフェッティ・情報カードの OK 待ち・延着表示は禁止。
5. **定時運行**: 運行終了直後の短いカプセルのみ。

シート presentation はシステム detents。発行祝祭に celebration spring の使い回しはしない。

ノイズになるパララックス・常時グローは禁止。

## やらないこと

- 紫グラデ / 汎用 SaaS ダーク / クリーム×テラコッタ×セリフ（**祝祭の水色マルス券紙は例外**）
- カスタム FAB・Hub 上の半透明オーバーレイ・ボトムバー追加 UI（発券シート内の KB 直上親指帯・削除 Undo バナー・祝祭オーバーレイは可）
- 絵文字アイコンの多用
- コーチング吹き出し
- ストリーク / XP / 定時率ゲージ / コンフェッティ
- Web / Flutter 風の独自カードグリッドを「ブランド」にする行為
- フルスワイプと Alert の二重確認、同一 View への `.alert` 重ね
- 発行と到着を同じ「スクリム＋角丸トースト」に揃えること

## 実装マップ

| ファイル | 役割 |
|----------|------|
| `DesignSystem/TrainTheme.swift` | adaptive 色・余白・型・`Motion.gaugeSnap` 等 |
| `DesignSystem/MarsTicketSpec.swift` | マルス券の比率・紙色・発行尺（固定。セマンティック色にしない） |
| `DesignSystem/MarsTicketView.swift` | 未使用マルス券面（発行・到着待ちで共有） |
| `DesignSystem/TrainChrome.swift` | Focus 純黒ダッシュボード・進捗バー・計器バンク・SignalBadge |
| `DesignSystem/DeleteConfirmation.swift` | フルスワイプ削除 + Undo バナー |
| `DesignSystem/EstimateSnapMapping.swift` | 見積もり分↔線形位置の純関数・sticky デテント |
| `DesignSystem/EstimateSnapGauge.swift` | KB 直上の線形スナップ・ゲージ |
| `DesignSystem/TicketIssueEject.swift` | 単発発行のマルス排出＋読ませるホールド（下スワイプで早めにはける） |
| `DesignSystem/ArrivalInvalidateOverlay.swift` | 到着: 検札印を自分でドン |
| `DesignSystem/PunctualityMomentOverlay.swift` | 定時運行の短いカプセル |
| `DesignSystem/TicketStackLayout.swift` | Hub 読める peek デッキの純関数レイアウト |
| `Core/History/Punctuality.swift` | 帯域判定（当初見積もり）。スコアを持たない |
| `TodoTrainWidget/FocusTimerPhase.swift` | App + Widget 共有の段階色ロジック |
| `TodoTrainWidget/CockpitLayoutContract.swift` | Live Activity 公称サイズ契約・密度選択 |
| `TodoTrainWidget/CockpitInstrumentViews.swift` | StandBy 2ペイン / LS ViewThatFits ダーク計器 |
| `ContentView.swift` | TabView + Focus cover |
| `Features/Hub/QuickAddBar.swift` | `QuickAddSheet`（親指発券帯） |
| `Features/Hub/TicketStackView.swift` / `HubMarsTicketCard.swift` | Hub マルス peek。focus は同一券の持ち上げ |
| `Features/Hub/HubTicketGateBand.swift` | 券面改札帯（発車）。Hub ドックや Focus 黒盤ではない |
| 履歴 / 設定 | 標準 List / Form |

## 横向き（iPhone compact height）

トリガー: `verticalSizeClass == .compact`（`EnvironmentValues.isCompactHeight`）。iPad 分割ビューは v2 スコープ外。

| 原則 | 内容 |
|------|------|
| 高さは希少 | large title を inline に、サマリー・ヘッダを 1 行化 |
| 幅は密度 | 行内メタ・タグを横展開。空き幅のダッシュボード化はしない |
| Hub 2 ペイン | compact 時は左 280pt に運行＋停車、右にマルス券スタック（単一 List の横伸びはしない） |
| 骨格維持 | Hub スタック + Form / cabin。マスター・ディテール分割・FAB は増やさない |
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
