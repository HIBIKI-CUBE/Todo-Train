# エンベロープと暗号

正本。13 と矛盾させない。実装は [README.md](README.md) のフィクスチャを読む。

## Encoding

ワイヤ上のバイト列はすべて **unpadded base64url**（RFC 4648 §5、末尾 `=` なし）。hex は使わない。QR の `x` / `y` と同じ。

UUID は小文字 canonical（`8-4-4-4-12`）。時刻は Unix **整数秒**（ミリ秒ではない）。

## 曲線と HKDF

- DH: **X25519**。公開鍵は raw 32 byte（SPKI ではない）。
- 共有秘密 32 byte を、許可後 Keychain の `masterKey` として保存する。ペアリング中の HKDF IKM も同じ共有秘密。
- HKDF-SHA256、L=32。
- **salt** = `pairingId` の RFC 4122 16 byte（文字列ではない）。
- info 文字列（UTF-8、これ以外を足さない）:

| 派生 | info | 用途 |
|------|------|------|
| `enc` | `todotrain/v1/enc` | AES-256-GCM |
| `tok` | `todotrain/v1/tok` | `writeToken`（32 byte）。サーバは SHA-256 ハッシュだけ保存 |
| `cfm` | `todotrain/v1/cfm` | confirm HMAC。画面に出さない |

`writeToken` の Bearer 値は unpadded base64url。`tokenHash` も SHA-256 生 32 byte の unpadded base64url。

## AES-256-GCM エンベロープ

HTTP / WS に載せる JSON:

```json
{ "rev": 42, "kind": "snap", "n": "<b64u 12 byte>", "ct": "<b64u>" }
```

- `n`: 12-byte nonce。
- `ct`: ciphertext **と** 16-byte tag（この順、1 本）。
- `kind`: `snap` / `cmd` / `ack`。
- `rev`: 平文メタ。snap はペアリング内で単調増加（新しい値は現在より大きい）。cmd / ack の `rev` もエンベロープに載せる（AAD 用）。cmd は送信側が選ぶ単調なカウンタでよい。
- サーバは `ct` を decode して JSON.parse しない。`rev` と `kind` だけ見る。

### AAD

UTF-8 バイト列:

```
{pairingId}|{kind}|{rev}
```

例: `a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea|snap|42`

- `pairingId` は小文字 UUID。
- `kind` は `snap` / `cmd` / `ack`。
- `rev` は先頭ゼロなし十進。`0` は可。
- 区切りは ASCII `|`。これ以外の結合は不可（kind の長さが可変なため）。

既知鍵ベクトル: [vectors/aes-gcm-snap.json](vectors/aes-gcm-snap.json)。

## Confirm HMAC

bind のあと、双方 LA 成功後:

```
HMAC-SHA256(cfmKey, UTF-8("{pairingId}|{offerId}|iphone"))
HMAC-SHA256(cfmKey, UTF-8("{pairingId}|{offerId}|mac"))
```

出力 32 byte を unpadded base64url で `POST .../confirm-*` の `hmac` に載せる。両方の到着が `confirmOverlapWindowSeconds` 以内に重なったときだけ pairing 確定。画面に出さない。

## Snap 平文

フィールドは [fixtures/snap.json](fixtures/snap.json)。乗務なしは [fixtures/snap-idle.json](fixtures/snap-idle.json)（`sessionId` と他の乗務欄は `null`、`phase` は `idle`）。声掛けのある snap は [fixtures/snap-nudge.json](fixtures/snap-nudge.json)。`serviceActive` / `cabinEnabled` / `checkInFiredCount` / `pendingCabin` は乗務なしでも載せる。欠ける旧 snap は `serviceActive=false`、`cabinEnabled=true`、`checkInFiredCount=0`、`pendingCabin=null`。`pendingCabin` は `progress` / `away` / `idle` / `overrun` / `gap` / `null`。未知値は表示だけ無視。`idle` は運行中で乗務が無いとき。Hub か PiP が出ているあいだは画面に出す。どちらの画面も出ていないときだけ、`notifyOn` の端末が通知する。1段目は既存の `progress`。`progress` は通知にしない。`overrun` は見積もり時刻と引き継ぎ、`gap` は到着後の空白。旧 Mac は未知の `pendingCabin` を無視する。`lastActivityAt` は載せない。

任意の `nudge` / `nudgePlan` / `reserved` は声掛け。欠けていても旧クライアントは無視する。値があるときだけ出す。欄が欠けた snap と、この欄を持つ snap の両方を、いまの型が読む。どれかの値が壊れていても、その欄だけ捨てて snap の復号は続ける。

`nudge` はいま出ている声掛け。`id`、`kind`（`progress` / `overrun` / `gap`）、`stage`（`checkIn` / `approach` / `estimate` / `handoff1` / `handoff2` / `handoff3` / `gap1` / `gap2`）、`ringSurface`（`mac` / `iphone` / `none`）、`firedAt`（Unix 整数秒）。未知の `kind` / `stage` / `ringSurface` は文字列のまま残し、snap の復号は続ける。`ringSurface` に `watch` を足すのは #100。

`nudgePlan` はまだ来ていない段の配列。各要素は `stage`、`fireAt`（Unix 整数秒）、`surface`（`ringSurface` と同じ語）、`rings`（鳴らすとき true）。

`reserved` は到着後に発車できる切符。`ticketId`、`title`、`estimatedSeconds`。無ければキーを置かない。

`estimatedSeconds` は当初見積ではなく **いまの予算（延長込み）**。iOS の `WorkSession.budgetSecondsAtStart` に対応する。

任意の `nextBlockTitle` / `nextBlockStartsAt` / `nextBlockEndsAt` は乗務中のいま、なければ次の占有（ダイヤまたは掲示）。欠けていても旧クライアントは無視する。Encode は値があるときだけ出す。時刻と分は Date からクライアントが床する。残り秒は送らない。一行だけ。Hub のいま＋次の二行は iPhone 側。`timetablePauseAt` はもう出さない。古い Mac は、この時刻になると `heldBy: timetable` の停車を一度送っていた。無いので、その停車は送られない。古い snap に残っていても、新しい Mac は停車を送らない。

任意の `notifyOn` / `notifyTurn` / `notifyFireAt` は、どちらの画面も出ていないときの通知の番。`notifyOn` は `iphone` / `mac` / `none`。`notifyTurn` は 0 から 3 の整数。`notifyFireAt` は Unix 整数秒。見積もり超過の発火時刻は残り秒から求めるので、ここには置かないことがある。欠けていても旧クライアントは無視する。未知の `notifyOn` は捨てて、snap の復号は続ける。値が無いときはキーごと省く。`none` はどちらの端末も出さない。Mac は `notifyOn` が `mac` のときだけ、自分の端末の通知を出す。プッシュは使わない。在席が決まらない snap は `iphone` を載せる。

任意の `pauseHeldBy` は停車中の理由。`user` / `timetable` / `alarm` / `switch` / `passenger`。`phase` が `paused` のときだけ出す。走行中・乗務なし・超過ではキーを置かない。欠けていても旧クライアントは無視する。未知の文字列は残し、snap の復号は続ける。停車中の例は [fixtures/snap-paused.json](fixtures/snap-paused.json)。

任意の `pauseId` は開いている停車。`phase` が `paused` のときだけ出す。欠けていても旧クライアントは無視する。壊れた値は捨てて、snap の復号は続ける。

任意の `macSampledSeconds` と `macActiveSeconds` は、その停車に残っている測った秒。`phase` が `paused` のときだけ、二つ揃えて出す。Mac は再起動したとき、ここから続きを測る。欠けていても旧クライアントは無視する。負の値、入力ありが見ていた秒を超えるとき、片方だけ、壊れた値は捨てて、snap の復号は続ける。

任意の `build` は**その平文を書いた側**のビルド。`{ "sha", "dirty", "schema", "builtAt" }`。`sha` は 7 桁、`schema` はストアの版（`3.0.0`）、`builtAt` は ISO 8601。欠けていても旧側は無視する。項目が欠けた `build` オブジェクトも、その平文の復号は続け、`build` だけ捨てる。値が無いときはキーごと省く。snap と ack を書くのは iPhone なので、そこでの `build` は iPhone のもの。Mac のビルドは cmd の任意 `build` に載せる（cmd は Mac → iPhone。ack のスロットは iPhone → Mac のままなので、Mac の SHA を ack に載せても iPhone には届かない）。

任意の `contract` と `minReadable` は、その平文を書いた側の約束の版。snap と ack は iPhone、cmd は Mac。キーが無い相手は版 3（`minReadable` も 3）とみなす。片方だけ、または整数でない値も版 3。リレーは `ct` を開かないので、この比較には加わらない。相手の `contract` が自分の `minReadable` 以上なら互換。相手のほうが新しいときは、知っている部分だけで続ける。相手が自分の `minReadable` を下回るときは、snap の読み取りは続け、操作の送信だけ止める。版のずれでは同期を切らない。

購読者の残り（Date 計算。残り秒を送らない）:

```
pausedTotal    = pausedAccumulated + (pausedAt != null ? now - pausedAt : 0)
elapsedActive  = now - startedAt - pausedTotal
remaining      = estimatedSeconds - elapsedActive
```

`now` / `startedAt` / `pausedAt` は Unix 整数秒。`pausedAccumulated` は **完了した停車区間の合計秒**（いま停車中なら `pausedAt` 以降は上式の第二項）。未知の `phase` は表示だけ保守的に落とす。

例: `startedAt=1768000000`, `estimatedSeconds=1500`, `pausedAccumulated=0`, `pausedAt=null`, `now=1768000120` → `remaining=1380`。

## Cmd / ack 平文

- cmd: [fixtures/cmd-pause.json](fixtures/cmd-pause.json) / [fixtures/cmd-resume.json](fixtures/cmd-resume.json) / [fixtures/cmd-still.json](fixtures/cmd-still.json) / [fixtures/cmd-issueAndBoard.json](fixtures/cmd-issueAndBoard.json) / [fixtures/cmd-answer-extend.json](fixtures/cmd-answer-extend.json) / [fixtures/cmd-boardReserved.json](fixtures/cmd-boardReserved.json) / [fixtures/cmd-presence.json](fixtures/cmd-presence.json) / [fixtures/cmd-pause-input.json](fixtures/cmd-pause-input.json)。`op` は `pause` / `resume` / `still` / `issueAndBoard` / `answer` / `boardReserved` / `presence` / `pauseInputReport`。`arrive` と `extend` は足さない。知らない `op` は実行せず、ack の `error` を `unsupportedOp` にする。受信側の約束が、その `op` を足した版（[enums.json](enums.json) の `opIntroduced`）より前のときも `unsupportedOp`。受信側はそこで落ちない。`still` はいまの車内放送 pending を消費する。`sessionId` は任意（乗務なし idle は `null`。例: [fixtures/cmd-still-nosession.json](fixtures/cmd-still-nosession.json)）。
- `answer` は iPhone が出した声掛けへの返事。`nudgeId`、`choice`（`stillOnIt` / `willExtend` / `alreadyDone` / `paused`。export の `checkIns.answer` と同じ語）、`answeredOn`、任意の `addSeconds`。`addSeconds` は `willExtend` のときだけ置き、値は 300 / 600 / 900（5・10・15分）。それ以外は `invalidPayload`。`answeredOn` はいま `mac` だけ。未知の文字列は復号でき、適用は `invalidPayload`。`watch` を足すのは #100。`sessionId` がいまの乗務と違うときは `sessionMismatch`、`nudgeId` がいまの声掛けと違うときは `nudgeStale`（[fixtures/ack-nudgeStale.json](fixtures/ack-nudgeStale.json)）。新しい Mac は snap に `nudge` があるときだけ `answer` を送る。旧 iPhone は `nudge` を載せないので、この op を受けない。例: [fixtures/cmd-answer-extend.json](fixtures/cmd-answer-extend.json)（延長）、[fixtures/cmd-answer-arrive.json](fixtures/cmd-answer-arrive.json)（到着）。
- `boardReserved` は予約の切符を発車する。`ticketId`、任意の `nudgeId`。`sessionId` は `null`。乗務中に受けたら `sessionMismatch`。`ticketId` が snap の `reserved.ticketId` と違えば `reservationChanged`。予約が無ければ `noReservation`。運行外は `noActiveService`。例: [fixtures/cmd-boardReserved.json](fixtures/cmd-boardReserved.json)。
- `presence` は Mac の在席。`pipVisible` と `attending`。変化したときだけ送る。`sessionId` は `null`。後続は、この値で Mac の画面に出ているかを判断する。例: [fixtures/cmd-presence.json](fixtures/cmd-presence.json)。
- `pause` の任意 `heldBy` は Mac が付ける停車の理由。送ってよいのは `user`（PiP の停車と車内放送の 4 択の停車）と `timetable`（明示したときだけ。時計では送らない）だけ。`alarm` / `switch` / `passenger` や未知の値は `invalidPayload` で、停車は適用しない。キーが無いのは古い Mac。理由は `user` と推定し、停車記録の `heldByInferred` を立てる。保護境界の前後では理由を変えない。推定の旗はワイヤに載せない。例: [fixtures/cmd-pause.json](fixtures/cmd-pause.json)（理由なし）、[fixtures/cmd-pause-timetable.json](fixtures/cmd-pause-timetable.json)（`timetable`）。新しい Mac が古い iPhone に `heldBy` を送っても、古い iPhone は知らないキーを捨てて停車だけを適用する。
- `pauseInputReport` は Mac が測った停車中の入力。`sessionId`、`pauseId`、`macSampledSeconds`、`macActiveSeconds`、`at`。任意の `promptedAt`（問いを出した Unix 秒）と `promptAnswer`（`resume` / `keepPaused` / `none`）。`none` は問いを出して答えが無い。問いを出していないときは両方省く。秒が負、または入力ありが見ていた秒を超えるときは `invalidPayload` で、記録は変えない。未知の `promptAnswer` も `invalidPayload`。同じ `pauseId` の秒は、残っている値と届いた値の大きい方だけを残す。入力ありは見た秒を超えない。`promptedAt` と `promptAnswer` は、まだ無いときだけ書く。停車が終わったあとは、秒が上がるときだけ足し、問いの答えは変えない。走行時間は変えない。停車が終わったときと、問いに答えたときに送る。例: [fixtures/cmd-pause-input.json](fixtures/cmd-pause-input.json)。
- リレーは `ct` を開かない。範囲が重なる名乗り（版を名乗らない端末と、いま入っている版 4 を含む）の cmd はそのまま通す。名乗りが `minReadable` を外れたときは、いままで通り 426 と `contractRange`。`unsupportedOp` は受信側の ack であり、リレーの HTTP エラーにはしない。
- `issueAndBoard` はこの op のときだけ `title`（trim 後非空。母艦 `Ticket.title` に文字数上限は無い）と `estimatedSeconds`（60〜3600。1〜60分。5分刻み以外も可）を載せる。他の op ではこの 2 キーを置かない。`sessionId` は非乗務なら `null`、乗務中の割り込みならいまの乗務の id（不一致は `sessionMismatch`）。運行外は `noActiveService`。題名や秒が不正なら `invalidPayload`。成功 ack は `ok: true` のみ。切符 id は ack に載せない。結果は後続 snap。例: [fixtures/cmd-issueAndBoard.json](fixtures/cmd-issueAndBoard.json)（非乗務）、[fixtures/cmd-issueAndBoard-interrupt.json](fixtures/cmd-issueAndBoard-interrupt.json)（割り込み）。
- ack 成功: [fixtures/ack-ok.json](fixtures/ack-ok.json)。`ok: true` のとき `error` キーは置かない。任意の `build` があるときだけ足す。無い ack はいままで通り。
- ack 失敗: [fixtures/ack-pauseLimitReached.json](fixtures/ack-pauseLimitReached.json)。`error` は [enums.json](enums.json) のみ。タイトルは載せない。
