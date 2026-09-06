# 13 — 同期構成（確定）

最終更新: 2026-09-06。土管・暗号・ペアリング契約。**画面の話はしない。**  
Mac の体験は別紙 [14-mac-companion-ux.md](14-mac-companion-ux.md)（確認待ち）。

この PR では実装しない。次の実装 PR の契約。

## 決めたこと

| 項目 | 決定 |
|------|------|
| 誰が本尊か | iPhone の SwiftData + `SessionManager`。リレーは正本にしない |
| 何を運ぶか | 暗号化スナップショット（いまの乗務）と暗号化コマンド（いまは `pause`） |
| 土管 | Hono on Cloudflare Workers + pairing 1 つ = Durable Object 1 つ |
| ローカル通信 | **主経路にしない。** 社内 Wi-Fi はクライアント分離・mDNS 遮断があり得る |
| 機密 | 正規ユーザー以外は中身を見られない。Apple / 自前サーバ / 押収を含む |
| 起こし | **求めない。** iOS は前面、または `ScenePhase.active` 復帰で送受信 |
| 手間 | アカウント・CRDT・APNs・LAN スタック・切符全件レプリカを足さない |
| 認証 | アカウントなし。QR ペアリング + write token |

**採用: ペアリング + E2E + CF Durable Object。**  
**不採用: SwiftData CloudKit（この土管）、LAN Bonjour（v1）、アカウント、WebAuthn PRF 主鍵、APNs。**

CloudKit ゲート（`CloudKitSync.isConfigured == false`）は維持。有料 Apple Developer Program はこのフェーズでは不要（App Store / 本番プッシュまで）。

クライアントが Mac メニューバーであることは同期の前提にしない。同じ契約を満たす購読者ならよい。体験の最小面は [14](14-mac-companion-ux.md)。

---

## なぜこの形か

起こしを求めないので、自前 HTTPS + WebSocket は Personal Team のまま動く。ADP 回避は成立する。

LAN 直結は遅延も E2E も強いが、社内ネットでは届かないことが多い。インターネット上の不透明リレーが主経路。LAN は後で足せる最適化で、v1 に入れない。

CloudKit は鍵が Apple 側なので「正規ユーザー以外不可」を満たさない。暗号文だけ載せるなら SwiftData 自動同期の旨味が消え、自前同期と同じ仕事になる。

---

## 役割

```
iPhone（本尊）                         relay（読めない）              購読者（例: Mac）
 SwiftData / SessionManager            pairing 1 = Durable Object     snap を購読
 前面: WebSocket                       ciphertext + rev だけ          cmd を置く
 復帰時: 取得 + コマンド適用            コマンド FIFO（暗号化）
```

- 発車の真実は open `WorkSession`
- ベル / LA / 車内放送は既存の `boardedDeviceID`。コマンドの実行は iPhone の `SessionManager`
- サーバはタイトルを見ない。復号できない正本をマージしない

---

## 認証: アカウントなしペアリング

メール / パスワード / パスキーアカウントは出さない。QR をどこに出すかは [14](14-mac-companion-ux.md)。

iPhone が一度だけ生成して Keychain に置く:

| 値 | 長さ | サーバ |
|----|------|--------|
| `pairingId` | UUID | 識別子。公開してよい |
| `masterKey` | 32 bytes | **送らない** |
| `writeToken` | 32 bytes | SHA-256 ハッシュだけ保存 |

QR（または同じ内容のテキスト）:

```
todotrain://pair?p=<pairingId>&k=<masterKey_b64u>&t=<writeToken_b64u>
```

購読者も同じ 3 つを Keychain へ。以降の HTTP / WS は `pairingId` + Bearer `writeToken`。サーバは `sha256(writeToken)` と照合するだけ。

リカバリは QR と同じ 3 値を一度だけ紙またはパスワードマネージャへ。両方の端末と紙を失ったら戻さない。iCloud にマスター鍵を置かない。

WebAuthn PRF は主鍵にしない。Face ID は Keychain のアクセス制御で足りる。

改ざん: AES-GCM なので、トークンを盗んだ攻撃者はキューを壊せてもクライアントは復号失敗で捨てる。ロールバックは `rev` の単調増加だけ採用。サーバ侵害の残りは削除 DoS。許容する。

---

## 暗号

HKDF-SHA256(`masterKey`)。サーバに渡すのは ciphertext だけ。

| 派生鍵 | info | 用途 |
|--------|------|------|
| `enc` | `todotrain/v1/enc` | AES-256-GCM |
| （token は別乱数） | — | サーバ認証。enc と混ぜない |

エンベロープ: `n`（12-byte nonce）+ `ct`。AAD は `pairingId || kind || rev`。`kind` は `snap` / `cmd` / `ack`。

### スナップショット平文

切符全件ではない。いまの乗務だけ。

```json
{
  "rev": 42,
  "sessionId": "…",
  "ticketId": "…",
  "title": "…",
  "phase": "running",
  "startedAt": 0,
  "estimatedSeconds": 1500,
  "pausedAccumulated": 0,
  "pausedAt": null,
  "boardedDeviceID": "…"
}
```

時刻は Unix。購読者の残り表示は Date 計算（`SessionClock` 相当）。残り秒を送ってポーリングしない。乗務なしは `sessionId: null`。

`phase` は既存の `SessionPhase` 文字列（`running` / `paused` / `overtime` 等）。未知値は表示だけ保守的に落とす。

### コマンド平文

```json
{ "id": "uuid", "op": "pause", "sessionId": "…", "at": 0 }
```

v1 の `op` は `pause` だけ。再開・到着・延長は同期契約に載せない。

### コマンド結果平文（ack）

iPhone が cmd を処理したら、成否を暗号化した ack を置く。購読者が「送信中」で固まらないため。

```json
{ "cmdId": "uuid", "ok": false, "error": "pauseLimitReached" }
```

`error` は `SessionError` に寄せる（`pauseLimitReached` / `noActiveService` / `sessionMismatch` 等）。平文のタイトルは載せない。

---

## リレー（Hono + Durable Object）

ペアリング 1 つ = Durable Object 1 つ。永続は DO ストレージ（R2 不要）。ポーリングしない。

| 面 | 役割 |
|----|------|
| `PUT /v1/pairings/:id` | 初回。`tokenHash` を登録 |
| `GET /v1/snap` | 最新 snap エンベロープ |
| `PUT /v1/snap` | iPhone が snap を置く。`rev` は単調 |
| `POST /v1/cmd` | 購読者が cmd を置く。短い FIFO |
| `GET /v1/cmd` | iPhone が未適用分を取る（復帰時の保険） |
| `PUT /v1/ack` | iPhone が直近 cmd の結果を置く |
| `GET /v1/ack` | 購読者が結果を取る（復帰時の保険） |
| `WS /v1/ws` | snap / cmd / ack を接続中へ即時配信。Hibernation 可 |

認証: すべての面で Bearer `writeToken`。

iOS 前面と購読者が両方 WS にいるとき、cmd は即時。iOS が背面なら FIFO に残り、次の `active` で適用 → snap + ack。

---

## クライアントの同期責務

体験（ボタンのコピー、メニューバーかウィンドウか）は [14](14-mac-companion-ux.md)。ここでは送受信だけ。

**iPhone**

- `ScenePhase.active` と発車 / 停車 / 延長 / 到着のたびに snap を置く
- active 中は WS。切れたら出し直す。定期ポーリングはしない
- 受信 cmd を復号 → `sessionId` が今の open と一致 → `SessionManager` で実行 → snap + ack
- 不一致・復号失敗・`SessionError` は ack `ok: false`。snap は現状のまま

**購読者（Mac など）**

- WS で snap を受け、Date ベースで残りを描く
- 操作は cmd を置くだけ。ローカル SwiftData なし
- ack が来るまで同じ `cmdId` を再送しない。タイムアウト後は snap を正とする

---

## 工数を増やさないためにやらないこと

| やらない | 理由 |
|----------|------|
| アカウント / OAuth / WebAuthn | ペアリングで足りる |
| 切符・履歴の暗号化レプリカ / CRDT | 乗務スナップショットで足りる |
| APNs / Background Modes | 起こしを求めない |
| LAN / Bonjour / Multipeer | 社内ネットで届かない |
| サーバ側正本 DB / SwiftData 同期 | 復号できない |
| CloudKit を true にする | Apple が読める。ADP が要る |
| JSON エクスポートを同期代わり | 要件 X-07 |

将来足してよいもの: フレンドリな LAN、APNs 起こし、PRF wrapping、`resume` など追加 `op`、完全レプリカ。v1 のエンベロープを壊さない範囲で。

---

## 実装順（同期側）

1. リレー（Hono + DO）とエンベロープの契約テスト
2. iOS: Keychain、ペアリングペイロード、snap / cmd / ack

購読者 UI は [14](14-mac-companion-ux.md) が固まってから。いまのリポジトリではゲートもサーバも足さない。
