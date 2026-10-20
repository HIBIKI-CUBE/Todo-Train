# Todo train — Agent Guide

プロダクトの判断は `docs/` にだけある。**コードから読めること（画面の作り、ファイル配置、ワイヤのバイト）は docs に書かない。** 迷ったらコードと `sync/contract/` を見る。

## 必読

1. [docs/01-vision.md](docs/01-vision.md) — 誰のためか・哲学
2. [docs/03-terminology.md](docs/03-terminology.md) — 用語を言い換えない
3. [docs/02-requirements.md](docs/02-requirements.md) — 守ること・やらないこと・未決

触る面に応じて:

- 根拠・OS 制限 → [docs/07-research.md](docs/07-research.md)
- 真実源・CloudKit を足さない理由 → [docs/04-architecture.md](docs/04-architecture.md)
- 見た目の骨格 → [docs/12-ui-design.md](docs/12-ui-design.md)
- 同期のなぜ → [docs/13-sync-mac-companion.md](docs/13-sync-mac-companion.md)
- Mac の役割 → [docs/14-mac-companion-ux.md](docs/14-mac-companion-ux.md)
- カレンダーの体験摩擦 → [docs/17-calendar-experience.md](docs/17-calendar-experience.md)
- Mac の配布ビルド（署名なし、Gatekeeper、セルフホストの予備） → [docs/22-mac-build.md](docs/22-mac-build.md)
- Hub 接近クリアランス → [docs/approach-clear/](docs/approach-clear/) + Issue #61
- スキーマや約束を変えたあとの実機確認 → [docs/21-device-overwrite.md](docs/21-device-overwrite.md)

## 作業時の原則

- コーチではなく道具。定時は瞬間だけ（ストリーク・点数・定時率は足さない）。
- 型名は **`Ticket`**。走行の真実は **`WorkSession`（`endedAt == nil`）+ `SessionManager.reconcile()`**。
- 同一切符の大幅書き換えはしない。残りは途中下車 → 乗り継ぎ。全日 LA は張らない。
- 同期の約束の版の正本は `sync/contract/version.json` だけ。Swift の定数と Worker はここを写す。
- 足すだけ（任意キー、新しい op、新しい enum）は `contract` だけ上げる。古い側が誤読する変更（意味の変更、必須化、削除）は `minReadable` も上げる。
- 版の更新は `cd sync/worker && npm run contract:bump -- --note "一行"`。
- SwiftData の `@Model` に保存される宣言（名前・型・既定値・`@Attribute`・`@Relationship`）を変えたら、AppSchema に新しい版と移行段を足し、`node tools/schema/fingerprint.mjs --write` で `Todo train/App/AppSchema.fingerprint` を更新する。`@Transient`・計算プロパティ・メソッドは指紋に入らない。
- 最新より前の版の型（`AppSchemaV3`・`AppSchemaV3_1` など）は書き換えない。検査は `node tools/schema/guard.mjs`（CI `contract-guard` の schema fingerprint）。
- スキーマや約束を変える PR は [docs/21-device-overwrite.md](docs/21-device-overwrite.md) の実機確認を通す。
- 画面の文言は [docs/03-terminology.md](docs/03-terminology.md) の「文体」に従い、`tools/wording/check.py` を通す（CI `wording`）。
- iOS アプリと Mac companion だけ `ENABLE_USER_SCRIPT_SANDBOXING = NO`。ビルド情報の Run Script が `.git` を読むためで、プロジェクト全体の YES は残す。

## Cloud Agent / Linux

- iOS Simulator / 本格的な `xcodebuild test` は期待しない。純関数と `Todo trainTests` を優先する。
- Live Activity / Widget / 通知 / カメラは PR の Mac 検証に委ねる。
- Worker は `cd sync/worker && npm test`（CI `sync-worker`）。パッケージと E2E は `sync/linux-swift.sh test` と `./sync/e2e/run.sh`（CI `sync-swift`）。
- リレーのホストと preview の出し方は `sync/worker/README.md`。
- Mac companion の署名なし Release は CI `mac-companion`（`runs-on: xcode-27`）。落とす手順は [docs/22-mac-build.md](docs/22-mac-build.md)。

開発ブランチは `develop`。
