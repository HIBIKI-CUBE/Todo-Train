# TodoTrainCompanion

macOS メニューバー accessory と乗務中 PiP。体験の判断は [docs/14-mac-companion-ux.md](../docs/14-mac-companion-ux.md)。

1. リレー（手元なら `cd sync/worker && npm start`、結合なら `./sync/e2e/run.sh`）
2. スキーム `TodoTrainCompanion` を Mac で Run
3. iPhone は設定 → Mac → この Mac とつなぐ。Mac は未ペアならメニューバーをクリックするだけ

Release のリレー既定は `https://todo-train.hibiki-cube.dev`、DEBUG は `https://dev.todo-train.hibiki-cube.dev`。ローカル wrangler や PR プレビューは設定で上書きする。
