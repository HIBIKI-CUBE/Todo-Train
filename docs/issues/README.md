# Issue 化

このディレクトリの本文を GitHub Issue に貼る。`gh` は読取専用なので人間側で作る。

`develop` に [15-agent-work-plan.md](../15-agent-work-plan.md) が入ってから。

## 今（Linux / 手が離せないとき）

Mac を開かなくてよい。

```bash
gh issue create --title "SYNC-0: 同期契約を sync/contract に固定する" --body-file docs/issues/SYNC-0-contract.md
gh issue create --title "SYNC-1: Hono + Durable Object リレー" --body-file docs/issues/SYNC-1-relay.md
gh issue create --title "SYNC-2: Swift 同期パッケージ（Linux swift test）" --body-file docs/issues/SYNC-2-swift-package.md
gh issue create --title "SYNC-5: Linux で client と Worker を結合する" --body-file docs/issues/SYNC-5-linux-e2e.md
```

順: **0 だけ先** → マージ後に **1 と 2 を並列** → 両方マージ後に **5**。

エージェントには Issue URL と `docs/15-agent-work-plan.md` を渡す。

## あと（Mac が空いてから）

```bash
gh issue create --title "SYNC-3: iOS ペアリング UI と SessionManager 配線" --body-file docs/issues/SYNC-3-ios.md
gh issue create --title "SYNC-4: macOS メニューバー" --body-file docs/issues/SYNC-4-macos.md
```

今作らなくてよい。Linux 隊列を止めない。
