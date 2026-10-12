# sync/contract — ワイヤ契約の正本

最終更新: 2026-10-13。散文の背景は [docs/13-sync-mac-companion.md](../../docs/13-sync-mac-companion.md)。

**Swift（SYNC-2）も Worker（SYNC-1）も、ワイヤ形式の正はここだけ。** 実装ディレクトリに別のスキーマや「本当の」エンベロープを書かない。テストはこのディレクトリの JSON / 例を fixture として読む。

Worker は `ct` を JSON.parse しない。平文フィクスチャと AES-GCM ベクトルはクライアント側の round-trip 用。復号鍵を Worker テストに持たない。

新しい HTTP 経路も `arrive` / `extend` の `op` も、ここから足さない。`resume` は 2026-09-12、`still`（車内放送の消費）は 2026-09-12 に追加。`issueAndBoard`（発行＋発車の一拍。在庫のみは無し）は 2026-10-07 に追加。`answer`（声掛けへの返事）・`boardReserved`（予約の切符の発車）・`presence`（Mac の在席。変化したときだけ）は 2026-10-12 に追加。`pause` の任意 `heldBy` と snap の任意 `pauseHeldBy` は 2026-10-12 に追加。2026-10-13 の版 8 は車内放送の文言だけを足し、ワイヤの形は版 7 のまま。切符全件レプリカは載せない。`GET /v1/hint/:pairingId` だけ例外（平文 rev。暗号文は載せない）。

## ファイル一覧

| ファイル | 内容 |
|----------|------|
| [pairing-url.abnf](pairing-url.abnf) | `todotrain://pair` / `todotrain://pair-mac` |
| [pairing-url.examples.txt](pairing-url.examples.txt) | 黄金 URL 2 本 |
| [http.json](http.json) | HTTP 経路（メソッド、認証、成功/失敗、JSON 形） |
| [ws.json](ws.json) | `WS /v1/ws` テキストフレーム |
| [envelope.md](envelope.md) | encoding、AAD、HKDF、エンベロープ、残り計算 |
| [enums.json](enums.json) | `phase` / `kind` / `op` / `error` / `pendingCabin` / 声掛け / `heldBy` |
| [constants.json](constants.json) | offer TTL、confirm 窓、cmd FIFO |
| [version.json](version.json) | 約束の版。`contract` / `minReadable` / 指紋 / history。Swift と Worker はここを写す |
| [fixtures/snap.json](fixtures/snap.json) | 走行中 snap 平文 |
| [fixtures/snap-idle.json](fixtures/snap-idle.json) | 乗務なし snap 平文 |
| [fixtures/cmd-pause.json](fixtures/cmd-pause.json) | `op: pause` 平文（`heldBy` なし。古い Mac） |
| [fixtures/cmd-pause-timetable.json](fixtures/cmd-pause-timetable.json) | `op: pause`、`heldBy: timetable` |
| [fixtures/cmd-resume.json](fixtures/cmd-resume.json) | `op: resume` 平文 |
| [fixtures/cmd-still.json](fixtures/cmd-still.json) | `op: still` 平文 |
| [fixtures/cmd-still-nosession.json](fixtures/cmd-still-nosession.json) | `op: still`、乗務なし（`sessionId` null） |
| [fixtures/cmd-issueAndBoard.json](fixtures/cmd-issueAndBoard.json) | `op: issueAndBoard`、非乗務（`sessionId` null） |
| [fixtures/cmd-issueAndBoard-interrupt.json](fixtures/cmd-issueAndBoard-interrupt.json) | `op: issueAndBoard`、乗務中割り込み |
| [fixtures/ack-ok.json](fixtures/ack-ok.json) | 成功 ack 平文 |
| [fixtures/ack-unsupportedOp.json](fixtures/ack-unsupportedOp.json) | 未知の op を実行しなかった ack |
| [fixtures/ack-nudgeStale.json](fixtures/ack-nudgeStale.json) | 声掛けがもう無い ack |
| [fixtures/cmd-answer-extend.json](fixtures/cmd-answer-extend.json) | `op: answer`、`willExtend` と `addSeconds` |
| [fixtures/cmd-answer-arrive.json](fixtures/cmd-answer-arrive.json) | `op: answer`、`alreadyDone` |
| [fixtures/cmd-boardReserved.json](fixtures/cmd-boardReserved.json) | `op: boardReserved`、`sessionId` は null |
| [fixtures/cmd-presence.json](fixtures/cmd-presence.json) | `op: presence`。在席の区分 |
| [fixtures/snap-nudge.json](fixtures/snap-nudge.json) | 声掛けと予約のある snap |
| [fixtures/snap-paused.json](fixtures/snap-paused.json) | 停車中 snap。`pauseHeldBy` あり |
| [fixtures/hint.json](fixtures/hint.json) | 公開 hint（rev だけ） |
| [fixtures/v3/](fixtures/v3/) | 版 3 の凍結。中身は変えない |
| [fixtures/v4/](fixtures/v4/) | 版 4 の凍結。中身は変えない |
| [fixtures/v5/](fixtures/v5/) | 版 5 の凍結。中身は変えない |
| [fixtures/v6/](fixtures/v6/) | 版 6 の凍結。中身は変えない |
| [fixtures/v7/](fixtures/v7/) | 版 7 の凍結。中身は変えない |
| [vectors/aes-gcm-snap.json](vectors/aes-gcm-snap.json) | 既知鍵の AES-GCM と confirm HMAC。Worker は使わない |

固定 UUID / Unix / 鍵はフィクスチャ間で共有する（`pairingId` `a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea` など）。
