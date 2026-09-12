# TodoTrainCompanion

macOS メニューバー（SYNC-4）。Dock には出さない accessory。表示は `Packages/TodoTrainSync` の `MenuBarPresentation`。操作は停車と再乗車。

## 動かし方

1. ローカル Worker（`cd sync/worker && npm start` または `./sync/e2e/run.sh` が上げるもの）
2. Xcode スキーム `TodoTrainCompanion` を Mac で Run
3. iPhone 側は設定 → Mac → この Mac とつなぐ
4. Mac は未ペアならメニューバーを左クリックするだけで吹き出しがペアリングになる（別ウィンドウは出ない）
5. 設定は吹き出し右上の歯車、またはメニューバーを右クリック。連携の解除はそこ

設定のリレー URL 既定は Release が `https://todo-train.hibiki-cube.dev`、DEBUG が `https://dev.todo-train.hibiki-cube.dev`。以前の `http://127.0.0.1:8787` は起動時に develop へ上げる。ローカル wrangler や PR プレビュー（`https://pr-<n>.todo-train.hibiki-cube.dev`）は設定で上書きする。

## テスト

```bash
xcodebuild test -scheme TodoTrainCompanion -destination 'platform=macOS' \
  -only-testing:TodoTrainCompanionTests -parallel-testing-enabled NO
```
