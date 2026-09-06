# 13 — Mac 連携と同期（確定）

最終更新: 2026-09-06。この PR では実装しない。次の実装 PR の契約。

## 決めたこと

机の Mac メニューバー（走行中タイトル / 残り / 停車）用。要件:

| 項目 | 決定 |
|------|------|
| 用途 | A。机から停車。Hub / 履歴の完全レプリカはしない |
| ローカル通信 | **主経路にしない。** 社内 Wi-Fi はクライアント分離・mDNS 遮断があり得る |
| 機密 | 正規ユーザー以外は中身を見られない。Apple / 自前サーバ / 押収を含む |
| 起こし | **求めない。** iOS は前面で生きている前提。背面なら `ScenePhase.active` 復帰時に逐次反映 |
| 手間 | 最小。アカウント・CRDT・APNs・LAN スタックを足さない |

**採用: ペアリング + E2E + Hono on Cloudflare Workers + Durable Object。**  
**不採用: SwiftData CloudKit（Mac 土管）、LAN Bonjour（v1）、アカウント、WebAuthn PRF 主鍵、APNs。**

CloudKit ゲート（`CloudKitSync.isConfigured == false`）は維持。WP-I のスキーマ準備は残すが、Mac は待たない。有料 Apple Developer Program はこのフェーズでは不要（App Store / 本番プッシュを出すときまで）。

---

## なぜこの形か

Hono + CFW で ADP を避ける、は「背面起こし」が要るときに崩れる。今回は起こしを捨てたので、自前 HTTPS + WebSocket は Personal Team のまま動く。課金回避は成立する。

LAN 直結は遅延も E2E も最強だが、社内ネットでは届かないことが多い。インターネット上の不透明リレーが机の主経路になる。LAN は後で足せる最適化であり、v1 に入れない。

CloudKit はペアリング不要で工数は最小だが、鍵が Apple 側なので「正規ユーザー以外不可」を満たさない。暗号文だけ載せるなら SwiftData 自動同期の旨味が消え、自前同期と同じ仕事になる。

---

## 役割

```
iPhone（本尊）                         relay（読めない）              Mac（リモコン）
 SwiftData / SessionManager            pairing 1 = Durable Object     メニューバー
 前面: WebSocket                       ciphertext + rev だけ          スナップショット購読
 復帰時: 取得 + コマンド適用            コマンドキュー（暗号化）         停車コマンドを置く
```

- 発車の真実はいまどおり open `WorkSession`。Mac はストアを持たない
- ベル / LA / 車内放送は既存の `boardedDeviceID`。停車コマンドは iPhone の `SessionManager` が実行する
- サーバはタイトルを見ない。復号できない正本をマージしない

---

## 認証: アカウントなしペアリング

メール / パスワード / パスキーアカウントは出さない。

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

Mac が読み、同じ 3 つを Keychain へ。以降の HTTP / WS は `pairingId` + `writeToken`（TLS 上の Bearer）。サーバは `sha256(writeToken)` と照合するだけ。

リカバリは QR と同じ 3 値を一度だけ紙またはパスワードマネージャへ。両方の端末と紙を失ったら戻さない。iCloud にマスター鍵を置かない（Apple 隣接になる）。

WebAuthn PRF は主鍵にしない。新規端末の wrapping は後回し。Face ID は Keychain のアクセス制御で足りる。

改ざん: 中身は AES-GCM なので、トークンを盗んだ攻撃者はキューを壊せても Mac / iPhone は復号失敗で捨てる。ロールバックはクライアントが `rev` の単調増加だけ採用して防ぐ。サーバ侵害の残りは削除 DoS。許容する。

---

## 暗号

HKDF-SHA256(`masterKey`) で用途を分ける。サーバに渡すのは ciphertext だけ。

| 派生鍵 | info | 用途 |
|--------|------|------|
| `enc` | `todotrain/v1/enc` | AES-256-GCM |
| （token は別乱数） | — | サーバ認証。enc と混ぜない |

エンベロープ:

- `n`: 12-byte nonce
- `ct`: ciphertext
- AAD: `pairingId || kind || rev`（`kind` は `snap` または `cmd`）

スナップショット平文（小さい。切符全件ではない）:

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

時刻は Unix。Mac の残り表示は iPhone と同じ Date 計算（`SessionClock` 相当）。残り秒を送ってポーリングしない。運行なし / 停車済みは `sessionId: null` のスナップショット。

コマンド平文:

```json
{ "op": "pause", "sessionId": "…", "at": 0 }
```

v1 の op は `pause` だけ。再開は iPhone。

---

## リレー（Hono + Durable Object）

ペアリング 1 つ = Durable Object 1 つ。永続は DO ストレージで足りる（R2 不要）。ポーリングしない。

| 面 | 役割 |
|----|------|
| `PUT /v1/pairings/:id` | 初回。`tokenHash` を登録 |
| `GET /v1/snap` | 最新エンベロープ。`rev` 付き |
| `PUT /v1/snap` | iPhone が暗号化スナップショットを置く。`rev` は単調 |
| `POST /v1/cmd` | Mac が暗号化コマンドを置く。短い FIFO |
| `GET /v1/cmd` | iPhone が未適用分を取る（復帰時の保険） |
| `WS /v1/ws` | 接続中の端末へ snap / cmd を即時配信。Hibernation 可 |

認証: すべての面で Bearer `writeToken`。CORS はアプリだけ。

iOS 前面（Focus / アプリ active）と Mac メニューバー常駐が両方 WS にいるとき、停車は即時。iOS が背面なら DO にコマンドが残り、次の `active` で適用して新しい snap を返す。

---

## クライアントの振る舞い

**iPhone**

- `ScenePhase.active` と発車 / 停車 / 延長 / 到着のたびに snap を置く
- active 中は WS。切れたら出し直す。定期ポーリングはしない
- 受信 cmd を復号 → `sessionId` が今の open と一致 → `SessionManager` で停車 → 新 snap
- 不一致・復号失敗は捨ててログ

**Mac（未着手・最小）**

- メニューバー: タイトル、Date ベースの残り、停車ボタン
- Hub は持たない
- WS で snap を描く。停車は cmd を置くだけ。ローカル SwiftData なし

---

## 工数を増やさないためにやらないこと

| やらない | 理由 |
|----------|------|
| アカウント / OAuth / WebAuthn | ペアリングで足りる |
| 切符・履歴の暗号化レプリカ / CRDT | Mac v1 に不要 |
| APNs / Background Modes | 起こしを求めない |
| LAN / Bonjour / Multipeer | 社内ネットで届かない |
| サーバ側正本 DB / SwiftData 同期 | 復号できない |
| CloudKit を true にする | Apple が読める。ADP が要る |
| JSON エクスポートを同期代わり | 要件 X-07 |

将来足してよいもの: フレンドリな LAN のショートカット、APNs 起こし、PRF wrapping、再開コマンド、完全レプリカ。v1 の契約を壊さない範囲で。

---

## 実装順（次の PR 群）

1. リレー（Hono + DO）とエンベロープの契約テスト
2. iOS: Keychain、ペアリング QR、snap 送信、cmd 適用
3. macOS メニューバー最小

いまのリポジトリではゲートもサーバも足さない。
