# Issue 化

このディレクトリの本文を GitHub Issue に貼る。この環境の `gh` は読取専用なので、Issue は人間側で作る。

`develop` に [15-agent-work-plan.md](../15-agent-work-plan.md) が入ってから。

```bash
# リポジトリ根で。ラベルは無ければ省略可
gh issue create --title "SYNC-0: 同期契約を sync/contract に固定する" --body-file docs/issues/SYNC-0-contract.md
gh issue create --title "SYNC-1: Hono + Durable Object リレー" --body-file docs/issues/SYNC-1-relay.md
gh issue create --title "SYNC-2: Swift 同期パッケージ（UI なし）" --body-file docs/issues/SYNC-2-swift-package.md
gh issue create --title "SYNC-3: iOS ペアリングと停車コマンド適用" --body-file docs/issues/SYNC-3-ios.md
gh issue create --title "SYNC-4: macOS メニューバーコンパニオン" --body-file docs/issues/SYNC-4-macos.md
```

作る順は 0 →（1 と 2 を並列）→（3 と 4 を並列）。3 と 4 は Issue 自体は先に作ってよく、着手は 0 と 2（と結合時は 1）のあと。

各 Issue の先頭に「必読 / 触ってよいパス / 環境」がある。エージェントに渡すときは Issue URL と `docs/15-agent-work-plan.md` を指定する。
