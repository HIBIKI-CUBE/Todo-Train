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

全体印象: **Observation / NavigationStack / SwiftData versioned schema など近代的な骨格は既にある。** 負債の中心は「SessionManager と巨大 Feature View の集中」「singleton + AppRuntime の配線」「クロスターゲット重複」「副作用経路の `try?`」「Widget / Notifier のテストギャップ」。契約違反級の P0（CloudKit 真実分岐など）は見つかっていない。

深掘り（アーキテクチャ境界・バグ温床）で追加確定した論点: **`phase` / `activeSession` は DB のキャッシュ**、**LA handoff の consume 順**、**Hub と `board()` の発車可否重複**、**`try? save()` の広がり**、**Intent の二次 `ModelContext`**。

### 健全だった点

- `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject` は **ゼロ**。`@Observable` + `.environment` に揃っている。
- `NavigationView` なし。`NavigationStack` のみ。
- 走行ドメインは `SessionManager` 拡張に分割済み（ファイル 13、合計 ~2.6k 行）。神クラス化の途中だが、無秩序な巨大 1 ファイルではない。
- Sync は `TodoTrainSync` + Worker に切り出し済み。Ticket UI も `TodoTrainTicketUI` へ抽出済み（`TicketUIShim` で橋渡し）。Mac は snapshot 消費で SwiftData を持たない。
- `AppSchema` V1→V3 と migration plan / rebuild 経路がある。
- wording の CI 門がある。Worker `src/` に `any` なし。

---

## 3. 所見（優先度付き）

優先度の目安:

- **P0** — 契約違反・データ喪失・明らかな本番クラッシュ筋（今回なし）
- **P1** — 間欠バグ / 回帰コスト大 / 境界侵食が進行中
- **P2** — 重複・肥大・依存の古さ（計画的に削る）
- **P3** — 掃除・整合・将来の余裕

### P1 — バグ温床（先に鎖）

| ID | 所見 | 根拠 | 候補アクション |
|----|------|------|----------------|
| P1-9 | ~~**LA/Widget handoff が sessionID 不一致でも consume される**~~ | ~~pause/resume で先に consume~~ | **済**: peek → 照合 → 変異成功時だけ consume。超過の到着は Focus が既に出ているとき consume のみ（後から `arrive()` しない）。`FocusPendingActionTests` |
| P1-3 | ~~**到着など不可逆寄りの操作が握りつぶされる**~~ | ContentView LA arrive はキュー保持済。restore / AlarmKit も対応 | **済（一部）**: Hub / History / TicketDetail の undo restore は `errorAlert`。AlarmKit pause/resume は Logger。`try? pause` 等の別経路は残存 |
| P1-10 | ~~**`try? modelContext.save()` が SessionManager ホットパスに多い**~~ | ~~`try? save()` 散在~~ | **済（骨格）**: `saveBestEffort()` + ログ。着発は persist を戻してから return。away と ATS の通知は save 成功後。乗客の発車と非常ドアは save 成功後だけ reconcile。残りはログのみ |
| P1-11 | ~~**`phase` / `activeSession` はメモリ上のキャッシュ**~~ | ~~Focus `TimelineView` / PassengerClock が tick 所有~~ | **済**: `ForegroundReconcileScheduling` + `SessionManager` の foreground 1 Hz ループ（乗車中・乗客レーン）。`inactive` はループを維持し `background` だけ止める。`active` では `endAwayWatch` のあとで再開する。Focus / Passenger は表示用 Timeline のみ。`ForegroundReconcileSchedulingTests` |
| P1-12 | **App Intent が二次 `ModelContext` で発券** | `IssueTicketIntent` が `ModelContext(container)` を新規作成して save。`SessionManager` の mainContext / Hub 表示と一時的にずれる | merge 挙動のテスト、または Intent も `AppRuntime` 経由の単一書き込み口へ |

### P1 — 境界と配線

| ID | 所見 | 根拠 | 候補アクション |
|----|------|------|----------------|
| P1-1 | **SessionManager が横断関心**（搭乗・ダイヤ・車内放送・LA/ベル副作用・乗客・削除 Undo 連携） | `Core/Session/SessionManager*.swift` 合計 ~2663 行、拡張 13。プロパティに UI 向け haptic tick / quiet message / passenger chrome が同居 | 副作用を `DeviceSideEffects` / Timetable / Passenger へさらに外向き化。クエリ系は既に `+Queries`。次は「書き込みコマンド」と「読み取り投影」の分離 |
| P1-2 | **グローバル singleton + `AppRuntime` / `SessionPauseRuntime` 静的ハンドル** | `Todo_trainApp` が `AppRuntime.sessionManager` / `OvertimeNotifier.shared.sessionManager` / `SessionPauseRuntime.pauser` / `AlarmKitScheduler.shared.bind` を起動時に相互配線。`AppSettings.shared` / `ArrivalForecastStore.shared` も Environment と二重 | Intents / Alarm / LA 用に「起動後のファサード 1 箇所」に閉じ、View 側は Environment のみを正にする。テストでは shared を避けられる形へ |
| P1-4 | **巨大 Feature / DesignSystem ファイル**（UI + 状態 + レイアウトが同居） | `CockpitInstrumentViews` 930 / `ArrivalInvalidateOverlay` 799 / `ApproachClearEngine` 792 / `HubView` 765 / `PassengerLCD` 602 / `FocusView` 596 など。ApproachClear 状態機械が `Features/` に居る | 純計算・状態機械を Core/Package へ。View は構成だけ。Widget 計器は既に `CockpitLayoutContractTests` があるので同じ型で切る |
| P1-13 | ~~**発車可否が Hub UI と `board()` で二重**~~ | ~~Hub と `board()` が別判定~~ | **済**: `BoardingEligibility` + `SessionManager.boardingEligibility`。Hub は `allowsInteraction` / `disabledReason`。`board()` は同一 gate。`BoardingEligibilityTests` |

### P1 — ライフサイクル・永続・テスト

| ID | 所見 | 根拠 | 候補アクション |
|----|------|------|----------------|
| P1-5 | **legacy `boardedDeviceID == nil` を自機扱い** | `SessionManager.ownsActiveRide` コメント。古いローカルデータの互換 | マイグレーションで埋める / 読み時に一度書き戻す期限を決める。永久互換にしない |
| P1-6 | **ModelContainer 生成失敗は `fatalError`** | `Todo_trainApp.init` | 個人データ前提なら起動失敗 UI の方が安全な場合あり（少なくともエラー内容を残す） |
| P1-7 | **未バージョン store の rebuild は破壊的フォールバック** | `AppModelContainer.rebuildPreservingData` — 失敗時に V1 として開き snapshot → 削除 → 復元 | 既にテストありそうだが、失敗モード（途中クラッシュ）の耐性を文書化・強化。監査ログを残す |
| P1-8 | **Notifier / Alarm / LA / Companion runtime は OS 結合が強く、単体テストが薄い** | `CheckInNotifier` / `OvertimeNotifier` / `AlarmKitScheduler` / `CompanionSyncRuntime` に専用テストヒントなし（純プロトコルはある）。`UNUserNotificationCenter.add` も完了ハンドラなし | Fake を通したスケジュール決定の表テストを増やす。OS 呼び出しはアダプタの向こうへ。スケジュール失敗を reconcile で検知 |

### P2 — 重複・整合・依存

| ID | 所見 | 根拠 | 候補アクション |
|----|------|------|----------------|
| P2-1 | **QR UI が iOS / Mac で二重** | `Features/Settings/QRViewfinderFrame.swift` と `TodoTrainCompanion/QRViewfinderFrame.swift`（現状同一）。`CompanionQRCodeView` は差分あり | 共有可能な描画を Package へ。プラットフォーム差だけ残す |
| P2-2 | **Package deployment target がアプリより古い** | アプリ `IPHONEOS_DEPLOYMENT_TARGET = 27.0`、Packages は `.iOS(.v17)` | 意図的ならコメントで固定。でなければ 27 に揃えて「古い API が混入しない」制約にする |
| P2-3 | ~~**`ServiceEndSheet` typealias 残骸**~~ | ~~`typealias ServiceEndSheet = ServiceShutdownCover`~~ | **済（本 PR）**: 参照ゼロのためファイル削除 |
| P2-4 | **`import CoreData` in ContentView** | `NSPersistentStoreRemoteChange` 購読に必要。未使用ではなかった | ゲート false のあいだ購読ごと狭めるなら P3-6 と一緒に |
| P2-5 | **Worker 依存のドリフト** | `npm outdated`: wrangler 4.129→4.149、vitest 4→5、workers-types 日付遅れ、hono patch 遅れ。TS major は別判断 | patch/minor を定期追従。vitest 5 / typescript 7 は別 PR |
| P2-6 | **CloudKit ゲートは正しく false だが、識別子と分岐が残存** | `CloudKitSync.isConfigured == false`、container id 文字列あり。`DeviceIdentifying` が同ファイル | ファイル分割（同期ゲート vs 端末 ID）。ゲート自体は契約どおり残す |
| P2-7 | **UITests が Xcode テンプレのまま** | `Todo_trainUITests` は launch のみ | 主要導線の煙テスト少数、またはターゲット縮小。現状はノイズ |
| P2-12 | **Hub 発車可否と `board()` の重複**（詳細は P1-13） | UI ヒントと throw が分岐し得る | P1-13 と同一スライスで潰す |
| P2-13 | **Widget フォルダ例外で app ターゲットに Widget ソースを共有** | `project.pbxproj` の TodoTrainWidget → app exceptions。`FocusTimerPhase` 等 | Cockpit/Timer を SPM モジュール化し、fragile な target membership をやめる |
| P2-14 | **Live Activity `update`/`end` が並列 Task** | `LiveActivityManaging` が `Task { await activity.update }` を連発 | 直列化 + 失敗ログ |
| P2-15 | **UI 層で `Calendar.current` と注入 calendar が混在** | Hub の WorkHourBand、History の一部、MarsTicket 日付面 | `sessionManager.calendar` / `@Environment(\.calendar)` に揃える |
| P2-16 | **ContentView がアプリライフサイクルの寄せ集め** | recover / focus cover / companion / away / remote store | `AppLifecycleCoordinator` へ切り出し（テストしやすくする） |

### P2 — テストギャップ（純関数優先）

| ID | 領域 | メモ |
|----|------|------|
| P2-8 | `ArrivalForecastEngine` / Trace | Store テストは厚い。Engine 単体を明示 |
| P2-9 | `CompanionSnapBuilding` / Runtime の決定表 | ペア状態・scenePhase・suppress 通知 |
| P2-10 | `EventKitCalendarBoard` のアダプタ境界 | Fit / Adoption / GuardLogic はテストあり。Board 実装の分岐を Fake 化 |
| P2-11 | Widget: `FocusTimerPhase` / snapshot decode | LayoutContract 以外の表示モデル |
| P2-17 | LA handoff / `IssueTicketIntent` | P1-9・P1-12 用の回帰テストが先 |

### P3 — 掃除・観測

| ID | 所見 | 候補 |
|----|------|------|
| P3-1 | Preview 内の `try!` 多用 | `#Preview` 専用ヘルパ（失敗時プレースホルダ）に寄せる |
| P3-2 | GeometryReader 多用 | 必要なものは残す。ネストだけ削る（Hub / Arrival / Focus） |
| P3-3 | `SWIFT_VERSION = 5.0` 表記 vs packages tools 6.0 | プロジェクト設定の意味を確認し、表記を実態に合わせる |
| P3-4 | ApproachClear / Hub / Companion の UserDefaults・通知 ID キー | `AppSettings.Keys` と同様、キー定数を一箇所に。`timetable.pause.` 接頭辞の散在も寄せる |
| P3-5 | `.build` 成果物が Packages 配下に残る可能性 | gitignore / クリーン手順の確認（エージェント環境のノイズ源） |
| P3-6 | CloudKit remote-change 購読がゲート false でも ContentView に残る | 死経路を狭めるかコメントで「将来用」と明示 |
| P3-7 | Mac companion の pause/resume 配線の軽い重複 | `CompanionPopover` vs `CompanionRideOverlayController` |

---

## 4. 推奨する進め方

一度に全部やらない。**縦スライスで「削って緑を保つ」**。

1. **~~死 alias 掃除~~** — P2-3 済。
2. **~~LA handoff の consume 順（P1-9）+ テスト~~** — 済。
3. **~~副作用の失敗を見える化（P1-3 / P1-10）~~** — `saveBestEffort` / restore alert / AlarmKit log 済。
4. **~~発車可否の単一 API（P1-13）~~** — 済。
5. ~~**reconcile スケジューラ（P1-11）**~~ — 済。
6. **SessionManager から投影を剥がす（P1-1）** — 書き込み API は触らない。次の実装スライス。
7. **クロスターゲット共有（P2-1 / P2-13）** — QR、Cockpit/Timer SPM。
8. **テストで鎖（P1-8 / P2-8–11 / P2-17）** — リファクタ PR は純関数テストを先に足す。
9. **依存更新は単独 PR（P2-5）** — アプリ本体と混ぜない。Dependabot high も別確認。

やらない方がいいこと:

- SessionManager の全面書き換え（乗り継ぎ原則と同じく、同一切符の大幅書き換えをしない）
- CloudKit を「ついでに」有効化
- UI 見た目の刷新と構造リファクタの同時進行

---

## 5. 次の調査で深掘りする候補

優先してコードリーディングを続けるなら:

1. ~~LA handoff / pending action の消費順~~ → P1-9 済
2. `SessionManager+DeviceSideEffects` / `recoverOnLaunch` / end-bell suppress の状態機械
3. `CompanionSyncRuntime` ↔ `CompanionMacRuntime` の責務対称性
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
