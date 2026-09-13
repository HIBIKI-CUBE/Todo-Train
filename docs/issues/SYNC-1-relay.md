必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)、`sync/contract/`（SYNC-0 マージ後）

## 環境

Node 22+ と Wrangler。**Xcode 禁止。** Linux Cloud Agent 向き。

## 触ってよいパス

- `sync/worker/**` のみ

読んでよい: `sync/contract/**`、`docs/13-sync-mac-companion.md`  
禁止: `Packages/**`、iOS/Mac ソース、CloudKit、アカウント。

## 目的

Hono + pairing 1 = Durable Object 1。サーバは ciphertext とメタだけ。復号しない。タイトルをログにも出さない。

## 実装

- `sync/worker` に Hono アプリ。`wrangler.toml` で DO をバインド
- 13 の経路: offers / bind / confirm-iphone / confirm-mac / pairings / snap / cmd / ack / WS
- bind は **双方の光学読取が揃ってから**。片側の QR 読取だけでは相手を固定しない
- confirm は画面に出ない HMAC。両方の到着が短い窓で重なったときだけ pairing 確定
- snap / cmd / ack は不透明バイト。中身を JSON.parse しない
- ポーリング API を「クライアントが回せ」と書かない。WS + 復帰時の GET 保険だけ
- 単体テスト: 契約の黄金バイト / JSON を fixture として読む。復号鍵はテストに持たない（平文フィクスチャは contract 側。Worker テストは opaque の載せ降とし）

デプロイ先の本番アカウントは必須にしない。`wrangler dev` / テストが通れば完了。人間の Mac は不要。

## 完了条件

- [ ] 契約の経路がテストで当たる
- [ ] 平文タイトルを Worker が読まない
- [ ] Xcode プロジェクトを dirty にしていない

## ブランチ

`cursor/sync-1-relay-…`。SYNC-0 が `develop` に入ってから。
