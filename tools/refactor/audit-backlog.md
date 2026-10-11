# リファクタ監査バックログ（2026-10）

コードから読める事実の棚卸し。プロダクト契約は `docs/` を正とし、ここは **技術負債の優先度メモ** だけを置く。

## 1. 見るべき観点（枠）

広い sweep の前に、次の軸で見る。軸同士は交差する（例: 巨大 View × 真実源の漏れ）。

| # | 観点 | 見るもの | このリポで特に効く理由 |
|---|------|----------|------------------------|
| A | **プロダクト不変条件との整合** | 走行の正が DB か / CloudKit ゲート / 確認の置き場 / KPI の芽 | `docs/02`・`04` が壊れると体験が崩れる |
| B | **アーキテクチャ境界** | Core vs Features、SessionManager の肥大、View 内ビジネスロジック | 変更コストと回帰範囲がここで決まる |
| C | **状態管理・DI** | `@Observable` / Environment / singleton / `AppRuntime` | Intents・通知・LA から同じ真実に届ける必要がある |
| D | **並行・ライフサイクル** | `@MainActor`、Task 取消、BackgroundTask、scenePhase | Focus / LA / ベル / 同期が同時に動く |
| E | **永続化・マイグレーション** | Schema Vn、rebuild 経路、legacy フィールド解釈 | 個人データの喪失は取り返しがつかない |
| F | **クロスターゲット重複** | iOS / Widget / Mac Companion / Packages | QR・計器・文言が二重化しやすい |
| G | **API・言語・ビルド設定** | 非推奨 API、deployment target 齟齬、Swift 6 隔離 | iOS 27 / Xcode 26 前提でも死角はある |
| H | **依存ライブラリ** | SPM / npm の古さ・互換性 | Worker と sync パッケージが別ライフサイクル |
| I | **バグの温床** | `try?` 握りつぶし、エラー無視、文字列キー、時計/TZ | 間欠バグになりやすい |
| J | **テスト可能性・カバレッジ** | Core 純関数 vs UI/OS 結合、UITests 空洞 | Cloud Agent はシミュレータに頼れない |
| K | **パフォーマンス・UI 熱** | 巨大 View、GeometryReader のネスト、tick | Hub / Focus / Widget が重い |
| L | **観測・診断・死コード** | typealias 残骸、未使用 import、DEBUG だけ生きる経路 | 迷子の入口を減らす |
| M | **セキュリティ・秘密** | ペアリング秘密、QR、リレー URL | Companion 同期の前提 |
| N | **アクセシビリティ・文言門** | Reduce Motion、wording CI | 既に tooling があるので回帰防止に使える |

意図的に後回しにするもの（この監査のスコープ外 / 契約どおり）:

- CloudKit を本番同期にすること（`docs/04` で禁止）
- 古い iOS へのフォールバック（`docs/01`: iOS 27 前提）
- 見た目の全面 redesign（`docs/12` の骨格変更は別トラック）

---

## 2. 調査サマリ

全体印象: **Observation / NavigationStack / SwiftData versioned schema など近代的な骨格は既にある。** 負債の中心は「SessionManager と巨大 Feature View の集中」「singleton + AppRuntime の配線」「クロスターゲット重複」「副作用経路の `try?`」「Widget / Notifier のテストギャップ」。

### 健全だった点

- `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject` は **ゼロ**。`@Observable` + `.environment` に揃っている。
- `NavigationView` なし。`NavigationStack` のみ。
- 走行ドメインは `SessionManager` 拡張に分割済み（ファイル 13、合計 ~2.6k 行）。神クラス化の途中だが、無秩序な巨大 1 ファイルではない。
- Sync は `TodoTrainSync` + Worker に切り出し済み。Ticket UI も `TodoTrainTicketUI` へ抽出済み（`TicketUIShim` で橋渡し）。
- `AppSchema` V1→V3 と migration plan / rebuild 経路がある。
- wording の CI 門がある。

---

## 3. 所見（優先度付き）

優先度の目安:

- **P0** — 契約違反・データ喪失・明らかな本番クラッシュ筋
- **P1** — 間欠バグ / 回帰コスト大 / 境界侵食が進行中
- **P2** — 重複・肥大・依存の古さ（計画的に削る）
- **P3** — 掃除・整合・将来の余裕

### P1 — 境界と配線

| ID | 所見 | 根拠 | 候補アクション |
|----|------|------|----------------|
| P1-1 | **SessionManager が横断関心**（搭乗・ダイヤ・車内放送・LA/ベル副作用・乗客・削除 Undo 連携） | `Core/Session/SessionManager*.swift` 合計 ~2663 行、拡張 13。プロパティに UI 向け haptic tick / quiet message / passenger chrome が同居 | 副作用を `DeviceSideEffects` / Timetable / Passenger へさらに外向き化。クエリ系は既に `+Queries`。次は「書き込みコマンド」と「読み取り投影」の分離 |
| P1-2 | **グローバル singleton + `AppRuntime` 静的ハンドル** | `Todo_trainApp` が `AppRuntime.sessionManager` / `OvertimeNotifier.shared.sessionManager` / `SessionPauseRuntime.pauser` / `AlarmKitScheduler.shared.bind` を起動時に相互配線。`AppSettings.shared` / `ArrivalForecastStore.shared` も Environment と二重 | Intents / Alarm / LA 用に「起動後のファサード 1 箇所」に閉じ、View 側は Environment のみを正にする。テストでは shared を避けられる形へ |
| P1-3 | **到着など不可逆寄りの操作が `try?` で握りつぶされる** | `ContentView.applyPendingFocusAction` の `try? sessionManager.arrive()`。Hub / History / TicketDetail の restore も `try?`。AlarmKit の pause/resume も同様 | 少なくとも arrive / restore はログ or ユーザー向け失敗経路。LA deep-link 失敗を黙殺しない |
| P1-4 | **巨大 Feature / DesignSystem ファイル**（UI + 状態 + レイアウトが同居） | `CockpitInstrumentViews` 930 / `ArrivalInvalidateOverlay` 799 / `ApproachClearEngine` 792 / `HubView` 765 / `PassengerLCD` 602 / `FocusView` 596 など | 純計算を Core/Package へ。View は構成だけ。Widget 計器は既に `CockpitLayoutContractTests` があるので同じ型で切る |

### P1 — バグ温床・ライフサイクル

| ID | 所見 | 根拠 | 候補アクション |
|----|------|------|----------------|
| P1-5 | **legacy `boardedDeviceID == nil` を自機扱い** | `SessionManager.ownsActiveRide` コメント。古いローカルデータの互換 | マイグレーションで埋める / 読み時に一度書き戻す期限を決める。永久互換にしない |
| P1-6 | **ModelContainer 生成失敗は `fatalError`** | `Todo_trainApp.init` | 個人データ前提なら起動失敗 UI の方が安全な場合あり（少なくともエラー内容を残す） |
| P1-7 | **未バージョン store の rebuild は破壊的フォールバック** | `AppModelContainer.rebuildPreservingData` — 失敗時に V1 として開き snapshot → 削除 → 復元 | 既にテストありそうだが、失敗モード（途中クラッシュ）の耐性を文書化・強化。監査ログを残す |
| P1-8 | **Notifier / Alarm / LA / Companion runtime は OS 結合が強く、単体テストが薄い** | `CheckInNotifier` / `OvertimeNotifier` / `AlarmKitScheduler` / `CompanionSyncRuntime` に専用テストヒントなし（純プロトコルはある） | Fake を通したスケジュール決定の表テストを増やす。OS 呼び出しはアダプタの向こうへ |

### P2 — 重複・整合・依存

| ID | 所見 | 根拠 | 候補アクション |
|----|------|------|----------------|
| P2-1 | **QR UI が iOS / Mac で二重** | `Features/Settings/QRViewfinderFrame.swift` と `TodoTrainCompanion/QRViewfinderFrame.swift`（現状同一）。`CompanionQRCodeView` は差分あり | 共有可能な描画を Package へ。プラットフォーム差だけ残す |
| P2-2 | **Package deployment target がアプリより古い** | アプリ `IPHONEOS_DEPLOYMENT_TARGET = 27.0`、Packages は `.iOS(.v17)` | 意図的ならコメントで固定。でなければ 27 に揃えて「古い API が混入しない」制約にする |
| P2-3 | ~~**`ServiceEndSheet` typealias 残骸**~~ | ~~`typealias ServiceEndSheet = ServiceShutdownCover`~~ | **済（本 PR）**: 参照ゼロのためファイル削除 |
| P2-4 | ~~**未使用 `import CoreData`**~~ | ~~`ContentView.swift` のみ~~ | **済（本 PR）**: 削除 |
| P2-5 | **Worker 依存のドリフト** | `npm outdated`: wrangler 4.129→4.149、vitest 4→5、workers-types 日付遅れ、hono patch 遅れ。TS major は別判断 | patch/minor を定期追従。vitest 5 / typescript 7 は別 PR |
| P2-6 | **CloudKit ゲートは正しく false だが、識別子と分岐が残存** | `CloudKitSync.isConfigured == false`、container id 文字列あり。`DeviceIdentifying` が同ファイル | ファイル分割（同期ゲート vs 端末 ID）。ゲート自体は契約どおり残す |
| P2-7 | **UITests が Xcode テンプレのまま** | `Todo_trainUITests` は launch のみ | 主要導線の煙テスト少数、またはターゲット縮小。現状はノイズ |

### P2 — テストギャップ（純関数優先）

| ID | 領域 | メモ |
|----|------|------|
| P2-8 | `ArrivalForecastEngine` / Trace | Store テストは厚い。Engine 単体を明示 |
| P2-9 | `CompanionSnapBuilding` / Runtime の決定表 | ペア状態・scenePhase・suppress 通知 |
| P2-10 | `EventKitCalendarBoard` のアダプタ境界 | Fit / Adoption / GuardLogic はテストあり。Board 実装の分岐を Fake 化 |
| P2-11 | Widget: `FocusTimerPhase` / snapshot decode | LayoutContract 以外の表示モデル |

### P3 — 掃除・観測

| ID | 所見 | 候補 |
|----|------|------|
| P3-1 | Preview 内の `try!` 多用 | `#Preview` 専用ヘルパ（失敗時プレースホルダ）に寄せる |
| P3-2 | GeometryReader 多用 | 必要なものは残す。ネストだけ削る（Hub / Arrival / Focus） |
| P3-3 | `SWIFT_VERSION = 5.0` 表記 vs packages tools 6.0 | プロジェクト設定の意味を確認し、表記を実態に合わせる |
| P3-4 | ApproachClear / Hub の UserDefaults キー | `AppSettings.Keys` と同様、キー定数を一箇所に |
| P3-5 | `.build` 成果物が Packages 配下に残る可能性 | gitignore / クリーン手順の確認（エージェント環境のノイズ源） |

---

## 4. 推奨する進め方

一度に全部やらない。**縦スライスで「削って緑を保つ」**。

1. **即時・低リスク掃除（半日以内の粒度）**  
   P2-4 未使用 import、P2-3 死 alias、P3 系のキー定数寄せ。
2. **副作用の失敗を見える化**  
   P1-3。`arrive` / AlarmKit / restore の `try?` を優先。
3. **SessionManager から投影を剥がす**  
   P1-1。まず「読み取り専用の overview / chrome」を別型へ。書き込み API は触らない。
4. **クロスターゲット共有**  
   P2-1 QR、Widget 計器モデルの Package 化。
5. **テストで鎖をかける**  
   P1-8 / P2-8–11。リファクタ PR は必ず純関数テストを先に足す。
6. **依存更新は単独 PR**  
   P2-5。アプリ本体と混ぜない。

やらない方がいいこと:

- SessionManager の全面書き換え（乗り継ぎ原則と同じく、同一切符の大幅書き換えをしない）
- CloudKit を「ついでに」有効化
- UI 見た目の刷新と構造リファクタの同時進行

---

## 5. 次の調査で深掘りする候補

優先してコードリーディングを続けるなら:

1. `SessionManager+DeviceSideEffects` / `recoverOnLaunch` / end-bell suppress の状態機械
2. `CompanionSyncRuntime` ↔ `CompanionMacRuntime` の責務対称性
3. `ApproachClearEngine` の Hub 密結合度
4. SwiftData モデルの optional レガシーフィールド一覧（`boardedDeviceID` 以外）
5. Worker DO（pairing / directory）の型安全と `as unknown as` 箇所

---

## 6. 調査コマンドメモ

再現用（ローカル）:

```bash
# 巨大ファイル（.build 除外）
find "Todo train" TodoTrainCompanion TodoTrainWidget \
  Packages/TodoTrainTicketUI/Sources Packages/TodoTrainSync/Sources \
  -name '*.swift' -print0 | xargs -0 wc -l | sort -rn | head

# 旧 Observation 系が残っていないこと
rg -n 'ObservableObject|@Published|@StateObject|NavigationView' --glob '*.swift'

# 本番経路の try?
rg -n 'try\? sessionManager\.|try\? manager\.' --glob '*.swift' -g '!*Tests*'
```
