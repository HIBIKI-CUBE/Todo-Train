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

## GitHub Actions デプロイ

Durable Objects 付き Worker は Cloudflare の aliased preview URL（`wrangler versions upload --preview-alias`）を使えない。なので **ターゲットごとに別 Worker 名** で `wrangler deploy --name` する。

| きっかけ | Worker 名 | GitHub Environment |
|---|---|---|
| PR（open / sync） | `todotrain-sync-pr-<n>` | `sync-preview-pr-<n>` |
| `develop` へ push | `todotrain-sync-develop` | `sync-develop` |
| `main` へ push | `todotrain-sync` | `sync-production` |

PR を閉じると `sync-worker-preview-teardown` が `todotrain-sync-pr-<n>` を削除する。preview の DO は本番と共有しない。

リポジトリ secrets（Environment secrets では skip 判定に見えない）:

- `CLOUDFLARE_API_TOKEN` — テンプレート **Edit Cloudflare Workers**
- `CLOUDFLARE_ACCOUNT_ID`

無いときは deploy / teardown は skip。`npm test` は通る。fork の PR はデプロイしない。
