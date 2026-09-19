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
- Mac の役割 → [docs/14-mac-companion-ux.md](docs/14-mac-companion-ux.md)（確認 1–6 は確定）
- 人の確認ログ → [docs/16-wakeup-checklist.md](docs/16-wakeup-checklist.md)（2026-09-19 完了。次の実機待ちではない）
- カレンダーの体験を直す → [docs/17-calendar-experience.md](docs/17-calendar-experience.md)（契約は [02](docs/02-requirements.md) / [12](docs/12-ui-design.md)）

## 作業時の原則

- **コーチではなく道具。** 質問ウィザードや説教 UI を増やさない。
- **掃き出し摩擦を最小化。**
- **定時の喜びは瞬間だけ。** ストリーク・点数・定時率を足さない。超過で案内を取り下げない。
- 型名は **`Ticket`**（Swift の `Task` と衝突する）。
- 走行の真実は **`WorkSession`（`endedAt == nil`）+ `SessionManager.reconcile()`**。タイマーに置かない。
- 同一切符の大幅書き換えはしない。残りは **途中下車 → 乗り継ぎ**。
- Live Activity で全日運行を張らない（8 時間上限。[07](docs/07-research.md)）。

## Cloud Agent / Linux

- iOS Simulator / 本格的な `xcodebuild test` は期待しない。純関数と `Todo trainTests` を優先する。
- Live Activity / Widget / 通知 / カメラは PR の Mac 検証に委ねる。
- Worker は `cd sync/worker && npm test`（CI `sync-worker`）。パッケージと E2E は `sync/linux-swift.sh test` と `./sync/e2e/run.sh`（CI `sync-swift`）。
- リレーのホストと preview の出し方は `sync/worker/README.md`。

開発ブランチは `develop`。
