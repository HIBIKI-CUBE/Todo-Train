# sync/contract — ワイヤ契約の正本

最終更新: 2026-09-08。散文の背景は [docs/13-sync-mac-companion.md](../../docs/13-sync-mac-companion.md)。

**Swift（SYNC-2）も Worker（SYNC-1）も、ワイヤ形式の正はここだけ。** 実装ディレクトリに別のスキーマや「本当の」エンベロープを書かない。テストはこのディレクトリの JSON / 例を fixture として読む。

Worker は `ct` を JSON.parse しない。平文フィクスチャと AES-GCM ベクトルはクライアント側の round-trip 用。復号鍵を Worker テストに持たない。

新しい HTTP 経路も `pause` 以外の `op` も、ここから足さない。

## ファイル一覧

| ファイル | 内容 |
|----------|------|
| [pairing-url.abnf](pairing-url.abnf) | `todotrain://pair` / `todotrain://pair-mac` |
| [pairing-url.examples.txt](pairing-url.examples.txt) | 黄金 URL 2 本 |
| [http.json](http.json) | HTTP 経路（メソッド、認証、成功/失敗、JSON 形） |
| [ws.json](ws.json) | `WS /v1/ws` テキストフレーム |
| [envelope.md](envelope.md) | encoding、AAD、HKDF、エンベロープ、残り計算 |
| [enums.json](enums.json) | `phase` / `kind` / `op` / `error` |
| [constants.json](constants.json) | offer TTL、confirm 窓、cmd FIFO |
| [fixtures/snap.json](fixtures/snap.json) | 走行中 snap 平文 |
| [fixtures/snap-idle.json](fixtures/snap-idle.json) | 乗務なし snap 平文 |
| [fixtures/cmd-pause.json](fixtures/cmd-pause.json) | `op: pause` 平文 |
| [fixtures/ack-ok.json](fixtures/ack-ok.json) | 成功 ack 平文 |
| [fixtures/ack-pauseLimitReached.json](fixtures/ack-pauseLimitReached.json) | 停車上限 ack 平文 |
| [vectors/aes-gcm-snap.json](vectors/aes-gcm-snap.json) | 既知鍵の AES-GCM と confirm HMAC。Worker は使わない |

固定 UUID / Unix / 鍵はフィクスチャ間で共有する（`pairingId` `a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea` など）。
