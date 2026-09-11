# SYNC-5 — Linux で client と Worker を結合する

暗号化クライアント（`Packages/TodoTrainSync`）がローカル Worker（`sync/worker`）と往復する。画面も生体も無い。LocalAuthentication は fake で即成功。人間の操作手順は無い。

## コマンド

リポジトリ根、またはこのディレクトリから:

```bash
./sync/e2e/run.sh
```

終端 0 なら完了。中でやること:

1. Worker 依存を入れて `wrangler dev` を立てる
2. Swift の結合テスト（オファー → 双方の光学文字列 → bind → 双方 confirm HMAC → snap PUT → GET/WS 復号 → pause cmd → 評価 `apply` → ack）
3. 片側の光学だけ、または confirm が片側だけ、では pairing が確定しない
4. Worker ログに平文タイトルが出ないことを確認して終わる

`swift test` だけ回すときは先に Worker を立て、`TODOTRAIN_SYNC_E2E_URL`（既定 `http://127.0.0.1:8787`）を渡す。Linux では `../../sync/linux-swift.sh test`（swift-crypto / BoringSSL 用の C++ フラグ）。手順の正本は `run.sh`。GitHub Actions は `sync-swift`。
