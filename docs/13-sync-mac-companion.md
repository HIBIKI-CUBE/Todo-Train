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
| 認証 | アカウントなし。QR は使い捨てオファーのみ。長期鍵は載せない。SAS 一致のあとマスター鍵を確定 |

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

メール / パスワード / パスキーアカウントは出さない。画面の出し方は [14](14-mac-companion-ux.md)。

**QR / スクリーンショット / 録画に長期秘密を載せない。** 撮られても中身の暗号は解けない。オファーを先に取られた場合は、iPhone の許可が出る前に正規 Mac 側が失敗するので、番号が自分の Mac と一致しない限り拒否できる。

### 長期秘密（許可が終わったあと Keychain）

| 値 | 長さ | サーバ |
|----|------|--------|
| `pairingId` | UUID | 識別子。公開してよい |
| `masterKey` | 32 bytes | **送らない。QR にも出さない** |
| `writeToken` | 32 bytes | SHA-256 ハッシュだけ保存。QR に出さない |

### オファー（QR に載せてよいもの）

短命。TTL 約 90 秒。先着 1 回だけ accept できる。

```
todotrain://pair?p=<pairingId>&o=<offerId>&x=<iPhone_eph_pub_b64u>
```

ここにあるのは識別子と **一時的な公開鍵だけ**。マスター鍵も write token も入らない。テキスト貼り付けも同じペイロードで、同じく秘密ではない。

### 手順

1. iPhone が X25519 一時鍵を作り、リレーにオファーを置く
2. 購読者が QR を読み、自分の一時鍵で `accept`（先着のみ）
3. 双方が DH → HKDF で `masterKey` / `writeToken` / SAS（短い照合数字）を派生する。この時点では **まだ Keychain に確定しない**
4. 双方が同じ SAS を出す。iPhone だけが「許可 / 拒否」。SAS は鍵ではない（切り詰めた照合用）
5. 許可: Keychain に長期秘密を書き、`tokenHash` をリレーへ。オファーは捨てる
6. 拒否・期限切れ・スクリーンショット / 画面収録を検出: オファーを捨てて作り直す。確定済みの鍵はまだ無い

先に他人が `accept` すると、正規 Mac は「この QR は使われました」。iPhone は他人の SAS を出す。自分の Mac に同じ数字が無いので拒否する。録画に QR だけ残っていても、許可なしではマスター鍵は確定しない。録画に SAS が写っていても、SAS から鍵は戻らない。

スクリーンショット通知と `UIScreen.isCaptured` ではオファーを無効化する（防御の重ね。主防御は QR に秘密が無いこと）。点滅 QR で秘密を分割する方法は使わない。録画で全フレームが残る。

リカバリを出すなら書き写し用の語または hex だけ。**リカバリを QR にしない**（撮影耐性を再び捨てる）。画面収録中は隠す。ウィザードで強制保存はしない。

WebAuthn PRF は主鍵にしない。Face ID は Keychain のアクセス制御で足りる。

改ざん: AES-GCM なので、トークンを盗んだ攻撃者はキューを壊せてもクライアントは復号失敗で捨てる。ロールバックは `rev` の単調増加だけ採用。サーバ侵害の残りは削除 DoS。許容する。

残る攻撃は、他人が先に `accept` した SAS を、ユーザーが照合せず許可すること。コピーは「Mac に同じ番号があるときだけ許可。番号を教える必要はない」。

---

## 暗号

HKDF-SHA256 の入力は、許可後は `masterKey`。ペアリング中は DH 共有秘密。サーバに渡すのは ciphertext と、オファー用の一時公開鍵だけ。

| 派生鍵 | info | 用途 |
|--------|------|------|
| `enc` | `todotrain/v1/enc` | AES-256-GCM |
| `sas` | `todotrain/v1/sas` | 照合数字（鍵ではない） |
| `tok` | `todotrain/v1/tok` | writeToken。enc と混ぜない |

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
| `POST /v1/offers` | iPhone。短命オファー（eph pub、TTL） |
| `POST /v1/offers/:id/accept` | 購読者。先着 1 回。相手の eph pub を返す |
| `POST /v1/offers/:id/confirm` | iPhone 許可。このあと `tokenHash` が生きる |
| `DELETE /v1/offers/:id` | 拒否・期限切れ・収録検出 |
| `PUT /v1/pairings/:id` | confirm 後。`tokenHash` を登録 |
| `GET /v1/snap` | 最新 snap エンベロープ |
| `PUT /v1/snap` | iPhone が snap を置く。`rev` は単調 |
| `POST /v1/cmd` | 購読者が cmd を置く。短い FIFO |
| `GET /v1/cmd` | iPhone が未適用分を取る（復帰時の保険） |
| `PUT /v1/ack` | iPhone が直近 cmd の結果を置く |
| `GET /v1/ack` | 購読者が結果を取る（復帰時の保険） |
| `WS /v1/ws` | snap / cmd / ack を接続中へ即時配信。Hibernation 可 |

認証: snap / cmd / ack / WS は Bearer `writeToken`（confirm 後）。オファー面は TTL と先着だけで、長期権限を与えない。

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
| QR / 貼り付けに masterKey や writeToken を載せる | 録画・後ろからの撮影で中身ごと奪える |
| 点滅 QR で秘密を分割する | 画面収録で全フレームが残る |
| リカバリ鍵を QR にする | 同じ撮影耐性を捨てる |

将来足してよいもの: フレンドリな LAN、APNs 起こし、PRF wrapping、`resume` など追加 `op`、完全レプリカ。v1 のエンベロープを壊さない範囲で。

---

## 実装順（同期側）

1. リレー（Hono + DO）とエンベロープの契約テスト
2. iOS: Keychain、オファー QR、SAS 許可、snap / cmd / ack

購読者 UI は [14](14-mac-companion-ux.md) が固まってから。いまのリポジトリではゲートもサーバも足さない。
