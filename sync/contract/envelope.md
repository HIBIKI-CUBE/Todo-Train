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

フィールドは [fixtures/snap.json](fixtures/snap.json)。乗務なしは [fixtures/snap-idle.json](fixtures/snap-idle.json)（`sessionId` と他の乗務欄は `null`、`phase` は `idle`）。

`estimatedSeconds` は当初見積ではなく **いまの予算（延長込み）**。iOS の `WorkSession.budgetSecondsAtStart` に対応する。

購読者の残り（Date 計算。残り秒を送らない）:

```
pausedTotal    = pausedAccumulated + (pausedAt != null ? now - pausedAt : 0)
elapsedActive  = now - startedAt - pausedTotal
remaining      = estimatedSeconds - elapsedActive
```

`now` / `startedAt` / `pausedAt` は Unix 整数秒。`pausedAccumulated` は **完了した停車区間の合計秒**（いま停車中なら `pausedAt` 以降は上式の第二項）。未知の `phase` は表示だけ保守的に落とす。

例: `startedAt=1768000000`, `estimatedSeconds=1500`, `pausedAccumulated=0`, `pausedAt=null`, `now=1768000120` → `remaining=1380`。

## Cmd / ack 平文

- cmd: [fixtures/cmd-pause.json](fixtures/cmd-pause.json)。`op` は `pause` だけ。
- ack 成功: [fixtures/ack-ok.json](fixtures/ack-ok.json)。`ok: true` のとき `error` キーは置かない。
- ack 失敗: [fixtures/ack-pauseLimitReached.json](fixtures/ack-pauseLimitReached.json)。`error` は [enums.json](enums.json) のみ。タイトルは載せない。
