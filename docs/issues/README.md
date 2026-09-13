# Issue 化

このディレクトリの本文を GitHub Issue に貼る。`gh` は読取専用なので人間側で作る。

Linux 隊列（0 / 1 / 2 / 5）はコードが `develop` に入っている。Issue を後から作る必要は無い。

## あと（Mac が空いてから）

```bash
gh issue create --title "SYNC-3: iOS ペアリング UI と SessionManager 配線" --body-file docs/issues/SYNC-3-ios.md
gh issue create --title "SYNC-4: macOS メニューバー" --body-file docs/issues/SYNC-4-macos.md
```

今作らなくてよい。エージェントには Issue URL と `docs/15-agent-work-plan.md` を渡す。
