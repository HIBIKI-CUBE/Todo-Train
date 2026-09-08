必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)

## 環境

どれでも可（Linux Cloud Agent でよい）。Xcode 不要。Node 不要。

## 触ってよいパス

- `sync/contract/**`（このチケットでディレクトリを作る）
- 契約の明確化に限った `docs/13-sync-mac-companion.md` の追記

禁止: `sync/worker/**`、`Packages/**`、Xcode、iOS/Mac UI。

## 目的

リレーと Swift が別エージェントで同時に書けるよう、**ワイヤ契約をファイルにする**。正本はコードではなくここ。

## 入れるもの

`sync/contract/` に少なくとも:

- `README.md` — ファイル一覧と「Swift / Worker はこれをテストする」
- Pairing URL の ABNF または例: `todotrain://pair?...` と `todotrain://pair-mac?...`
- HTTP / WS の経路一覧（13 の表を機械可読に。メソッド、認証、成功/失敗）
- エンベロープ: nonce / ciphertext / AAD のバイト順と encoding（hex または base64url を一つに決める）
- 平文 JSON の黄金例: `snap.json`、`cmd-pause.json`、`ack-ok.json`、`ack-pauseLimitReached.json`、乗務なし snap
- `phase` と `error` の列挙（既存 `SessionPhase` / `SessionError` に寄せる。13 と矛盾させない）
- HKDF `info` 文字列の一覧（`todotrain/v1/enc` 等）

新しいエンドポイントや `pause` 以外の `op` を発明しない。曖昧さがあれば 13 に合わせて短く直し、13 を更新する。

## 完了条件

- [ ] 上記ファイルがある
- [ ] 13 と矛盾するフィールドが無い
- [ ] Worker も Swift もこのディレクトリ以外にワイヤ形式を「正」と書かなくてよい

## ブランチ

`cursor/sync-0-contract-…`。1 PR。このチケットだけ。
