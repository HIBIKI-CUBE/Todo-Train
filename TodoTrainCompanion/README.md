# TodoTrainCompanion

macOS メニューバー（SYNC-4）。Dock には出さない accessory。表示は `Packages/TodoTrainSync` の `MenuBarPresentation`。操作は停車だけ。

## 動かし方

1. ローカル Worker（`cd sync/worker && npm start` または `./sync/e2e/run.sh` が上げるもの）
2. Xcode スキーム `TodoTrainCompanion` を Mac で Run
3. iPhone 側は SYNC-3（#35）の設定 → Mac → 画面をこの Mac に向ける

設定のリレー URL 既定は Release が `https://todo-train.hibiki-cube.dev`、DEBUG が `http://127.0.0.1:8787`。develop リレーは `https://dev.todo-train.hibiki-cube.dev`。PR プレビューは `https://pr-<n>.todo-train.hibiki-cube.dev` を設定で上書きする。

## テスト

```bash
xcodebuild test -scheme TodoTrainCompanion -destination 'platform=macOS' \
  -only-testing:TodoTrainCompanionTests -parallel-testing-enabled NO
```
