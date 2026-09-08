# SYNC-1 — Hono + Durable Object リレー

契約の正本は [`../contract/`](../contract/README.md)。このディレクトリは経路の実装だけ。

## 動き

- ペアリング 1 つ = `PairingDurableObject` 1 つ
- `offerId` と `tokenHash` の索引は `DirectoryDurableObject`（R2 / KV は使わない）
- サーバは `rev` / `kind` と不透明な `n` / `ct` だけ見る。`ct` を `JSON.parse` しない
- confirm HMAC は画面に出ない不透明バイト。cfm 鍵では検証しない（サーバは鍵を持たない）
- snap / cmd / ack の配信は `WS /v1/ws`（Hibernation）。ポーリング API は書かない
- ログに ct / hmac / token / 平文タイトルを出さない

## コマンド

```bash
cd sync/worker
npm install
npm test
npx wrangler dev
```

`npm test` は契約バイトのドリフト検査、src の不透明度検査、vitest（Workers 実行時）、`tsc` まで走る。同じコマンドを GitHub Actions `sync-worker` が PR と `develop` / `main` で回す（`sync/worker` か `sync/contract` が変わったとき）。

本番アカウントは不要。Linux で `npm test` が終端 0 なら完了。
