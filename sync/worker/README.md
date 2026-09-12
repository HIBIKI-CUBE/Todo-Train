# SYNC-1 — Hono + Durable Object リレー

契約の正本は [`../contract/`](../contract/README.md)。このディレクトリは経路の実装だけ。

## 動き

- ペアリング 1 つ = `PairingDurableObject` 1 つ
- `offerId` の索引は `DirectoryDurableObject`（R2 / KV は使わない）。`tokenHash` 索引はヘッダなしクライアント用。`X-Pairing-Id` があれば Directory を飛ばし、Pairing DO がハッシュを照合する
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

本番アカウントはテスト完了には不要。Linux で `npm test` が終端 0 なら品質ゲートは通る。

## GitHub Actions デプロイ

Durable Objects 付き Worker は Cloudflare の aliased preview URL（`wrangler versions upload --preview-alias`）を使えない。なので **ターゲットごとに別 Worker 名** で出す。カスタムドメインは `todo-train.hibiki-cube.dev` の下に載せる。preview / develop は本番ホストを奪わない。

| きっかけ | Worker 名 | 公開 URL | GitHub Environment |
|---|---|---|---|
| PR（open / sync） | `todotrain-sync-pr-<n>` | `https://pr-<n>.todo-train.hibiki-cube.dev` | `sync-preview-pr-<n>` |
| `develop` へ push / `workflow_dispatch` → develop | `todotrain-sync-develop` | `https://dev.todo-train.hibiki-cube.dev` | `sync-develop` |
| `main` へ push / `workflow_dispatch` → production | `todotrain-sync` | `https://todo-train.hibiki-cube.dev` | `sync-production` |

PR を閉じると `sync-worker-preview-teardown` が `todotrain-sync-pr-<n>` を削除する。preview の DO は本番と共有しない。

手元:

```bash
npx wrangler login
npm run deploy:develop
npm run deploy:production
```

## Cloudflare 側（一度だけ）

1. ゾーン **`hibiki-cube.dev`** を、デプロイする Cloudflare アカウントに置く（ネームサーバーを Cloudflare にする）。同じアカウントでないと Custom Domain は失敗する。
2. `todo-train.hibiki-cube.dev` / `dev.todo-train.hibiki-cube.dev` に既存の DNS レコードがあるときは消す。Wrangler が Custom Domain 用に作り直す。
3. API トークン: テンプレート **Edit Cloudflare Workers**。Zone リソースに `hibiki-cube.dev` を含め、**DNS Edit** が付いていること（Custom Domain が DNS レコードを書く）。
4. アカウント ID を控える。

Workers Paid は不要。SQLite バックエンドの Durable Objects は Free プランで動く。

## GitHub secrets

リポジトリ secrets（Environment secrets では skip 判定に見えない）:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

無いときは deploy / teardown は skip。`npm test` は通る。fork の PR はデプロイしない。
