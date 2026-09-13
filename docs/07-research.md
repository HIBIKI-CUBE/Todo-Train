# 07 — 研究根拠とプラットフォーム制約

設計判断の「なぜ」と、実装時に踏んではいけない制限。

## 1. 研究に基づく判断

| 設計 | 根拠 | 強度 |
|------|------|------|
| 停車上限 2（設定で 3） | 同時ゴール ≈2。**制限は新規発車**。停車そのものは逃げ道として常に可 | **強〜中** |
| 走行中 1 | シングルタスクング / 同上 | **強** |
| Inbox 無制限 / 停車は制限 | GTD capture vs clarify; [Risko & Gilbert 2016](https://doi.org/10.1016/j.tics.2016.07.008) 認知オフロード | **強** |
| 見積もり上限 60 分 | [Buehler et al. 1994](https://doi.org/10.1037/0022-3514.67.3.366) Planning Fallacy; unpacking で精度向上 | **中〜強**（「60」自体はヒューリスティック） |
| 途中下車 + 乗り継ぎ | [Masicampo & Baumeister 2011](https://doi.org/10.1037/a0024192) 計画で侵入思考低減; Ovsiankina 再開欲求 | **中** |
| 分割 > 書き換え | 認知負荷・表象変更コスト | **弱〜中** |
| 道具 > コーチ | [Barkley 1997](https://doi.org/10.1037/0033-2909.121.1.65) 外部化; 介入自体が EF を消費 | **中** |
| 見積もり校正は中央値 | Planning Fallacy 対策（平均より頑健） | **中** |
| 定時は帯域内・非通貨。到着は完了優先 | Goodhart: 測ると歪む。超過で祝祭を取り上げると責めになる。[Deci & Ryan SDT](https://doi.org/10.1037/0003-066X.55.1.68) 内発 > 点数 | **中** |

### 仮説（利用データで検証）

- 7 段階プリセット（5–60m）
- FAB 即キーボード / Mars 的操作
- セーフティロック Override UI
- Override 無制限でも WIP が破綻しないか
- 車内放送のジッター帯と本数（10 分以下 0 / 11–25 分 1 / 30 分以上 2）

### 停車上限 UX

警告のみは弱い。**新規発車をソフトブロック + 解決選択**（再乗車 / 途中下車 / 放棄）。臨時停車で枠を増やすのはやめる。

### 定時の喜び（ハック耐性）

「定時運行できたときの喜び」は残しつつ、人間が仕組みを最適化対象にしない。

| やる | やらない |
|------|----------|
| **まず到着できたことを祝う**（超過後も含む） | 超過を理由に案内を取り上げる（責めになる） |
| 早着はいい結果として「早着」＋見積/実績 | 早着を普通の到着に埋める / 延着バッジ |
| 定時は同じ案内の見出し味付け。見積/実績は定時・早着 | 超過の差分を祝祭で突き付ける |
| 当初見積もりで判定。延長後予算では見ない | 延長して「間に合わせた」ことにする |
| 消える瞬間 + haptic。履歴は「定時」「早着」「到着」 | ストリーク / XP / 定時率 / 解除 |
| 空の運行・到着ゼロは定時運行にしない | 運行開始→即終了で祝う |

早着を祝っても点数がないので、見積もり水増しをする理由は薄い。

---

## 2. Live Activities（ActivityKit）— 必須制約

出典: [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), WWDC26 Live Activities essentials 等。

### ハード上限（iOS 27 でも未緩和）

| 段階 | 上限 |
|------|------|
| アクティブ | **最大 8 時間**（システムが自動終了） |
| Dynamic Island | 終了と同時に消える |
| Lock Screen（終了後） | 最大 +4 時間（合計 12h） |

**結論: 全日「運行」を 1 本の LA で張り続けるのは不可能かつ非推奨。**

### その他の制約

- ContentState / push ペイロード ≈ **4KB**
- 開始は原則 **フォアグラウンド**（BG 黙再起動は拒否されうる）
- アプリ休眠中の任意更新は **push なしでは不可**
- 毎秒 update は非推奨 → `Text(timerInterval:)` / `ProgressView(timerInterval:)` に任せる
- push は時間あたり予算あり（`apns-priority: 10` は特に）
- 同時数は公式未公開（アプリあたり ~5 が通説）。Todo train は基本 **LA 1 本**

### 「運行中・未乗務」を LA に載せる案

**載せない。** 理由:

1. 8h で昼過ぎに死ぬ  
2. Apple の定義は “いま起きていること” — 空き時間の催促は弱い  
3. ユーザーが LA を切る・他アプリの DI を押しのける  
4. 継ぎ足しは HIG アンチパターン  

**代替:** Widget / アプリ内表示 / 控えめな通知（v1）

### 推奨パターン（Todo train）

| フェーズ | LA | 運行の空き |
|----------|-----|-----------|
| MVP | なし | アプリ内 |
| v1 | **発車中のみ**（残時間 + 停車/到着 Intent） | **Widget**「運行中・未乗務」 |
| v2 | Watch / StandBy 磨き | AlarmKit で終了ベル |

```
1 Live Activity = 走行中 1 件、または直近の停車中 1 件（最大 2 時間）
≠ 1 運行日
```

- 停車中切符は LA に並べない（直近 1 件だけ残す。別発車で切替）
- LA 削除 ≠ 運行キャンセル（DB が真実源）
- 停車中は `timerInterval` を止められない → **静的な残り時間**に切替
- AlarmKit は `pause` して LA を残す。Session LA も `update` のまま残す（`end` すると StandBy / Island が消える）
- 停車から 2 時間で破棄（ActivityKit 8h の手前）。アプリが死んでいる間は次の起動 / reconcile で掃除。セッションは停車のまま

---

## 3. AlarmKit（v2）— Live Activity と混同しない

- iOS 26+（WWDC25）。Focus / サイレントを突き破るアラーム・タイマー終了向け
- StandBy カウントダウン表示には **Live Activity（AlarmAttributes）が必須**
- 「運行を 8 時間表示する」手段ではない
- Todo train: **チケット予定終了の強制ベル** → **v2**
- 役割分離: **LA = 視線 / AlarmKit = 終了の強制通知**

参考: [WWDC25 — Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/)

---

## 4. Foundation Models / PCC

- iOS 26+: `FoundationModels` / `SystemLanguageModel`（オンデバイス、entitlement 不要）
- iOS 27+: `PrivateCloudComputeLanguageModel`（PCC）— entitlement `com.apple.developer.private-cloud-compute`
- 得意: 要約・抽出・分類・短い構造化出力。汎用チャットボットではない
- 対象端末: Apple Intelligence 対応 + ユーザー有効化（15 Pro Max 前提）
- 日次クォータあり。オフラインはオンデバイスのみ

適用優先度:

| 用途 | AI | 時期 |
|------|-----|------|
| 見積もり数値 | Heuristic で十分 | MVP |
| 到着整理の分割案 | PCC（ユーザー起動） | v1 |
| 日次レビュー文 | PCC / オンデバイス | v1 |

---

## 5. フォーカス「強制」の限界

| できる | できない |
|--------|----------|
| アプリ内 fullScreenCover で Hub を隠す | 他アプリの起動阻止 |
| スワイプ dismiss 禁止 | ホーム / App Switcher 阻止 |

仕様文言: **「アプリ内ではフォーカス画面を維持。OS レベルでは閉じ込めない」**

---

## 6. CloudKit / Apple Developer Program

SwiftData の `cloudKitDatabase: .private` は **有料 Apple Developer Program** の iCloud CloudKit container が要る。

- Personal Team（無料）: アプリのシミュレータ / 実機デバッグは可
- Personal Team に iCloud / CloudKit entitlement を足すと **署名失敗**
- CloudKit Console も有料チーム向け
- `@Attribute(.unique)` は SwiftData+CloudKit で使えないので、同期オンの前に外す

このリポジトリは `CloudKitSync.isConfigured == false` のあいだ `.none` でローカル保存する。同期の土管は CloudKit にしない（Apple が読める）。起こし（APNs）を求めないので、このフェーズの同期に有料 ADP は不要。契約は [13-sync-mac-companion.md](13-sync-mac-companion.md)。Mac 体験は [14-mac-companion-ux.md](14-mac-companion-ux.md)。

---

## 7. 主要出典リンク

- [ActivityKit — Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [WWDC26 Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/)
- [WWDC25 Foundation Models](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25 AlarmKit](https://developer.apple.com/videos/play/wwdc2025/230/)
- [Private Cloud Compute](https://developer.apple.com/private-cloud-compute/)
- [SwiftData CloudKit](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
