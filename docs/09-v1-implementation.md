# 09 — v1 実装ハンドオフ（Cloud Agent 向け）

この文書は **v1 を一気に実装する** Cloud Agent / 外部 Agent のための作業指示書です。  
前提ドキュメント: [01](01-vision.md)–[08](08-current-status.md)、ルート [AGENTS.md](../AGENTS.md)。

## 0. 環境制約（必読）

Cloud Agent は **Linux** 上で動く想定です。

| できること | できない / 弱いこと |
|------------|---------------------|
| ソース編集、純関数の設計、ドキュメント更新 | **iOS Simulator での `xcodebuild test` は不可**（または実質不可） |
| ロジックを切り出したユニットテストの**記述** | Live Activity / Widget / 通知 / SwiftUI の実行確認 |
| PR 作成・差分説明 | Foundation Models / PCC の実機推論 |
| 静的レビュー（用語・アーキテクチャ整合） | 実機の Time Sensitive 通知・Dynamic Island |

### 検証方針（必須）

1. **ビジネスロジックは純関数 / プロトコル化**し、`Todo trainTests` にテストを書く。
2. Cloud Agent は「テストが**書かれていること**」と「API 契約が docs と一致すること」までを完了条件にする。
3. PR 本文に **`Needs Mac verification`** チェックリストを必ず載せる（下記 §7）。
4. Linux で無理に iOS SDK ビルドを通そうとして時間を溶かさない。失敗したらスキップし、Mac 検証に委ねる。
5. Widget Extension / ActivityKit を追加する場合、**Xcode の File System Synchronized グループ**前提なら新規フォルダを正しいターゲットに入れる必要がある。`project.pbxproj` の扱いが不明なら、拡張ターゲット追加手順を PR に「人間が Xcode でターゲット作成」として明記してよい（コード本体はリポジトリに置く）。

## 1. v1 スコープ（確定パッケージ）

MVP 完了後の v1。**一度の大きな PR でも、スライス単位の複数 PR でもよい**が、下表の順序を守ること。

| 優先 | Work Package | 概要 | Linux で完結度 |
|------|--------------|------|----------------|
| P0 | **WP-A Settings** | 停車上限 2/3、超過音 ON/OFF | 高（UserDefaults + SessionManager） |
| P0 | **WP-B History v1** | 検索 + 「今日に追加」 | 高（純関数 + SwiftData） |
| P0 | **WP-C Reorder View** | 全切符 + フィルタ強調 + 手動 D&D | 中（UI 多い） |
| P1 | **WP-D dueDate** | 任意期限。自動ソートなし | 高 |
| P1 | **WP-E Custom estimate** | プリセット外の分入力（1–60） | 高 |
| P1 | **WP-F Live Activity** | **発車中のみ**。残時間・タイトル | 低（要 Mac） |
| P2 | **WP-G Home Widget** | 運行中 / 運休 / 停車数 | 低（要 Mac） |
| P2 | **WP-H AI / PCC** | 分割提案・日次レビュー（タップ起動のみ） | 低（要 Apple Silicon + AI） |
| P2 | **WP-I CloudKit** | 同期 + 単一走行ロック | 低（要アカウント/実機） |

### v1 に含めない（触るな）

- AlarmKit / StandBy（v2）
- JSON エクスポート
- OS レベルの集中ロック
- コーチング質問ウィザード
- 同一切符の大幅書き換え（乗り継ぎ分割のみ）
- 全日運行の Live Activity（8h OS 制限。`07-research.md`）

## 2. 共通設計ルール（破らない）

- 用語は [03-terminology.md](03-terminology.md) 厳守（到着 / 途中下車 / 乗り継ぎ / 臨時停車 等）。
- **道具**であること。説教・ウィザード・自動並べ替え禁止。
- セッション真実源: `WorkSession` + `SessionManager.reconcile()`（Date ベース）。
- モデル名 `Ticket`（Swift `Task` 禁止）。
- 見積もり上限 60 分。
- 走行中 1 / 停車デフォルト 2（設定で最大 3）。

## 3. Work Package 詳細

### WP-A — Settings

**ゴール**

- Hub から設定画面へ。
- 停車上限: `2`（デフォ）または `3`。
- 超過システム音: ON/OFF（`OvertimeOverlay.playAlertSound` をゲート）。

**実装指針**

- `UserDefaults` または小さな `AppSettings`（`@Observable`）。
- `SessionManager` の `pauseLimit` を設定から注入（起動時 / 変更時）。
- 既存 `PauseLimitGuard.defaultLimit` はフォールバックに残してよい。

**受入**

- [ ] 上限 3 にすると 3 枚目まで停車可、4 枚目でシート。
- [ ] 音 OFF で超過時にシステム音が鳴らない。
- [ ] テスト: 設定値を渡した `SessionManager` で上限挙動。

**主なファイル**

- 新規: `Features/Settings/SettingsView.swift`, `Core/Settings/AppSettings.swift`
- 変更: `HubView`, `Todo_trainApp`, `SessionManager` 初期化, `FocusView` / `OvertimeOverlay`

---

### WP-B — 履歴検索 + 今日に追加

**ゴール**

1. `HistoryView` に検索バー（タイトル部分一致、大小無視）。
2. 閉じた切符（または履歴行）から **「今日に追加」**: 同タイトル・同見積もり・同タグの**新しい open `Ticket`** を Hub 末尾に作成（繰り返しタスク機能ではない）。
3. 検索中は日次 sticky を簡略化してよい（マッチしたセッションだけ表示）。

**実装指針**

```swift
// 純関数例
enum HistorySearch {
  static func matches(session: WorkSession, query: String) -> Bool
}
enum TicketReissue {
  static func makeTodayCopy(from ticket: Ticket, sortOrder: Int) -> Ticket
}
```

- 「今日に追加」は **closed 切符のコピー**。Lineage は付けない（または `manual` で親リンク — **付けない方を採用**。単純コピー）。
- 運行の有無は問わない（Inbox 掃き出しと同じ）。

**受入**

- [ ] 空クエリで従来どおり全日表示。
- [ ] クエリでタイトルフィルタ。
- [ ] 今日に追加 → Hub に open 切符が増える。元の履歴は残る。
- [ ] テスト: フィルタとコピー生成。

**主なファイル**

- `Features/History/HistoryView.swift`, `HistorySessionRow.swift`
- 新規ヘルパー + `HistorySearchTests`

---

### WP-C — 並べ替えビュー

**ゴール**

- 専用画面: **すべての open 切符**を常時表示。
- フィルタ（タグ・見積もり範囲）は **強調（opacity / ボーダー）のみ**。非マッチを消さない。非マッチは並べ替え不可でも可。
- ドラッグで `sortOrder` 更新。システム自動ソートなし。
- Hub ツールバーから遷移（「並べ替え」）。

**受入**

- [ ] フィルタしても行は消えない。
- [ ] D&D で Hub の順序と同期。
- [ ] 自動で期限やタグにより並び替えない。

**主なファイル**

- 新規: `Features/Reorder/ReorderView.swift`
- 変更: `HubView` toolbar

---

### WP-D — 期限（dueDate）

**ゴール**

- `Ticket.dueDate: Date?`（任意）。
- Detail で DatePicker（optional clear）。
- Hub / Reorder で小さな表示のみ。**自動ソート・リマインダ通知はしない**（v1）。

**マイグレーション**

- SwiftData にプロパティ追加。破壊的移行が必要なら `AppModelContainer` で軽量対応を検討し、PR に手順を書く。

**受入**

- [ ] nil 可。設定・クリア可。
- [ ] 期限があっても Hub の並びはユーザーの `sortOrder` のまま。

---

### WP-E — カスタム見積もり入力

**ゴール**

- QuickAdd / Detail でプリセットに加え **1–60 の任意分**（Stepper またはテキスト）。
- 60 超は拒否。分解を促す短い文言は可（1 行まで、ウィザード禁止）。

**受入**

- [ ] 23 分などを設定できる。
- [ ] Heuristic ハイライトは従来どおりプリセット最近傍。

---

### WP-F — Live Activity（発車中のみ）

**ゴール**

- 発車で LA 開始、停車・到着・途中下車・放棄で終了。
- 表示: タイトル、残時間（カウントダウン）、超過表示。
- App Intent（任意だが推奨）: 停車 / 到着 — 失敗してもセッションは DB が本尊。

**制約**

- **運行日全体の LA は作らない**（8 時間制限。`07-research.md`）。
- Info.plist / ターゲット: ActivityKit、Supports Live Activities。

**受入（Mac / 実機）**

- [ ] 発車で Dynamic Island / ロック画面に出る。
- [ ] 停車で消える。
- [ ] Force-quit 後も再起動で整合（Session 復元優先）。

**Cloud Agent の完了定義**

- Activity attributes・更新フック・開始/終了呼び出しまでコード化。
- ターゲット追加が困難なら `Features/LiveActivity/` にソースを置き、`docs` に Xcode 手順を残す。

---

### WP-G — Home Screen Widget

**ゴール**

- 小/中: 運行中か運休か、停車 n 件、今日の集中ざっくり（任意）。
- Timeline は短め更新。セッション真実はアプリ側。

**Cloud Agent**: ソース + 手順。実行確認は Mac。

---

### WP-H — AI / PCC（差分設計）

**ゴール**

- `CoachingEngine` プロトコル（既存 Heuristic を実装として接続）。
- PCC / on-device は **ユーザーが明示タップしたときだけ**（到着整理の分割提案、日次レビュー）。
- 不可時は Heuristic にフォールバック。「Private Cloud で処理」注釈。

**Cloud Agent**: プロトコル境界と Heuristic 配線まで必須。実モデル呼び出しは stub + `#if` / availability でよい。

---

### WP-I — CloudKit

**ゴール**

- SwiftData + CloudKit 有効化。
- **走行中セッションは単一デバイス**（競合時は最新を残し他を recoveryConflict）。

**注意**: 個人開発でも署名・コンテナ設定が要る。Cloud Agent はスキーマ互換と競合方針のコードまで。コンテナ ID を勝手に本番化しない。

## 4. 推奨実装順序（1 本化する場合）

```
WP-A Settings
  → WP-B History search/reissue
  → WP-D dueDate（モデル変更を早めに）
  → WP-E custom estimate
  → WP-C Reorder view
  → WP-F Live Activity
  → WP-G Widget
  → WP-H AI stubs
  → WP-I CloudKit（最後・切り離し PR 推奨）
```

モデル変更（dueDate）は早い段階で入れ、UI は後追いでもよい。

## 5. ブランチ / PR 運用

- ベース: `develop`
- 作業ブランチ例: `feature/v1-pack` または WP ごと `feature/v1-history` …
- コミットメッセージはリポジトリの既存スタイルに合わせる（短い日本語 + 内容）。
- **コミットはユーザーが明示した場合のみ**（Agent ルール）。指示がなければ変更を残し、PR 作成指示を待つ。
- 大きな WP-I は独立 PR 推奨。

## 6. テスト規約

| 層 | 内容 |
|----|------|
| 必須 | 新規純関数の Swift Testing |
| 必須 | 既存 `Todo trainTests` を壊さない（Mac で回帰） |
| 任意 | UI テストは増やさない（不安定・Linux 不可） |
| 禁止 | 実機専用 API をテストのコンパイル必須パスに置く（モック/プロトコル） |

`SessionManager` に依存する機能は、既存どおり `FixedSessionClock` + in-memory `AppModelContainer`。

## 7. PR テンプレート（コピー用）

```markdown
## Summary
- v1: <WPs implemented>

## Cloud Agent notes
- Linux ではシミュレータ未実行
- 純関数テスト: <追加ファイル>

## Needs Mac verification
- [ ] xcodebuild test -only-testing:"Todo trainTests"
- [ ] Settings 停車上限 2/3
- [ ] 履歴検索 + 今日に追加
- [ ] 並べ替えビューのフィルタ強調
- [ ] dueDate 表示
- [ ] Live Activity 発車/停車（実機またはシミュレータ）
- [ ] Widget 表示
- [ ] （任意）CloudKit / AI

## Out of scope
- AlarmKit, 全日 LA, コーチングウィザード
```

## 8. 用語・文言クイックリファレンス

| UI | 意味 |
|----|------|
| 今日に追加 | 履歴の切符を **新規 open Ticket としてコピー** |
| 並べ替えビュー | 消さず強調。自動ソートなし |
| Live Activity | **発車中セッションのみ** |
| 臨時停車 | 既に MVP 実装済み。触るなら回帰のみ |

## 9. 完了の定義（v1 パック全体）

1. WP-A〜E がコード上マージ可能でテスト追加済み。
2. WP-F/G はソースと配線が存在（ターゲット未接続なら手順書あり）。
3. WP-H はプロトコル + Heuristic 接続 + stub。
4. WP-I は「やるなら独立・後回し可」。やらなくても v1 アプリ機能としては可とする場合、PR で明示。
5. `docs/08-current-status.md` と本ファイルのチェックを更新。
6. Mac 検証チェックリストが PR に残っている。
