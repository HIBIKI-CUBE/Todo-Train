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
| 認証 | アカウントなし。QR はオファーのみ。鍵は画面に出さない。双方の端末で本人確認が重なったときだけ確定 |

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

### 脅威（この契約の範囲）

| 範囲 | 内容 |
|------|------|
| 中 | iPhone と Mac の画面が **常時録画**されている。スクショ、後ろ撮り、後から映像を繰り返し見る |
| 中 | 映像を見ながら別のマシンで QR を読む |
| 外 | 端末に入力を打てるマルウェア、または本人の顔 / パスコードを使って `LocalAuthentication` を通せる状態。それは端末を操作しているのと同じ |

映像からペアできる状態にしてはいけない。画面に出るものはすべて漏れる前提。確定に必要なものは **画面に出ない秘密** と **その場の本人確認** だけにする。

### 長期秘密（双方の本人確認が終わったあと Keychain）

| 値 | 長さ | サーバ |
|----|------|--------|
| `pairingId` | UUID | 識別子。公開してよい |
| `masterKey` | 32 bytes | **送らない。画面にも QR にも出さない** |
| `writeToken` | 32 bytes | SHA-256 ハッシュだけ保存。画面にも QR にも出さない |

DH の共有秘密・HKDF の出力・confirm の HMAC も画面に出さない。照合数字（SAS）だけ出してよい。SAS は切り詰めで、鍵に戻せない。

### オファー（QR に載せてよいもの）

短命。TTL 約 90 秒。先着 1 回だけ accept できる。

```
todotrain://pair?p=<pairingId>&o=<offerId>&x=<iPhone_eph_pub_b64u>
```

識別子と一時公開鍵だけ。テキスト貼り付けも同じで、秘密ではない。

### 手順

1. iPhone が X25519 一時鍵を作り、リレーにオファーを置く
2. 購読者が QR を読み、自分の一時鍵で `accept`（先着のみ）
3. 双方が DH → HKDF で `masterKey` / `writeToken` / SAS を派生する。**まだ Keychain に書かない**
4. 双方が同じ SAS を出す（鍵ではない）
5. **iPhone で Face ID またはデバイスパスコード**（`LocalAuthentication`）。成功したら画面に出ない `HMAC(DH, "confirm"|iphone|offerId)` をリレーへ
6. **Mac で Touch ID またはログインパスワード**。同様に `confirm|mac` を送る
7. リレーは **両方の confirm が数秒以内に重なったときだけ** ペアを確定する。片方だけ・時間外・HMAC 不一致は捨てる
8. 確定後に Keychain へ書き、`tokenHash` を残す。オファーは捨てる
9. 拒否・期限切れ・背面へ行く・スクリーンショット / 画面収録: オファーを捨てて作り直す。確定前の鍵は残さない

映像に QR と SAS とボタンが全部写っていても、HMAC も生体も再生できない。別マシンで QR を読んでも、iPhone 本体の Face ID と、その DH 相手の Mac 本体の本人確認が同時に要る。録画を見ている第三者は、どちらの端末も操作していないので確定できない。

先に他人が `accept` すると、正規 Mac は「この QR は使われました」。iPhone の SAS は他人側と一致する。自分の Mac と違うので Face ID しない。

### 照合数字は「自分が読んだ」と冗長か

成功パスでは冗長に感じるのが自然。自分が Mac で QR を読んだなら、DH の相手はその Mac で、数字は必ず一致する。ここだけ見るとクイズに見える。

それでも残すのは合理的。理由は失敗パスで、**本人確認は「どの Mac か」を束縛しない**から。

| 起きること | 双方 LA だけ | 双方 LA + 照合 |
|------------|--------------|----------------|
| 自分が読んだ（成功） | 通る | 通る。数字は一致しているので一目で終わる |
| 録画や後ろ撮りで他人が先に `accept` | 他人の Mac が Touch ID、自分が Face ID すれば **他人と確定する** | iPhone の数字は他人側。机の Mac と違う / 机の Mac は「使われました」。Face ID しない |

「読んだのは自分」は意図であって、オファーの先着事実ではない。画面が録画される前提では、読んだ主体をアプリは区別できない。照合数字は DH 相手の指紋で、名前（「Hibiki の MacBook」）は相手が名乗れるので代用できない。

体験では別画面のクイズにしない。Mac が読み終わって数字を出した瞬間が、iPhone の Face ID シート（「この Mac ですか」）と重なる。打ち直しもしない。詳細は [14](14-mac-companion-ux.md)。

点滅 QR は使わない。録画で全フレームが残るうえ、本人確認の代わりにならない。

リカバリを出すなら書き写し用の語または hex だけ。**QR にしない。** 収録中は隠す。ウィザードで強制しない。書き写しはペア確定後の任意で、常時録画への耐性はペアリング本体とは別（紙に残した鍵の管理）。

WebAuthn PRF は主鍵にしない。Face ID は確定の本人確認と Keychain 保護の両方に使う。

改ざん: AES-GCM。ロールバックは `rev` 単調増加。サーバ侵害の残りは削除 DoS。許容する。

---

## 暗号

HKDF-SHA256 の入力は、許可後は `masterKey`。ペアリング中は DH 共有秘密。サーバに渡すのは ciphertext と、オファー用の一時公開鍵だけ。

| 派生鍵 | info | 用途 |
|--------|------|------|
| `enc` | `todotrain/v1/enc` | AES-256-GCM |
| `sas` | `todotrain/v1/sas` | 照合数字（鍵ではない。画面に出してよい） |
| `tok` | `todotrain/v1/tok` | writeToken |
| `cfm` | `todotrain/v1/cfm` | confirm HMAC。画面に出さない |

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
| `POST /v1/offers/:id/confirm-iphone` | iPhone。LA 成功後の HMAC。画面の数字ではない |
| `POST /v1/offers/:id/confirm-mac` | Mac。同様。両方の到着が重なったときだけ確定 |
| `DELETE /v1/offers/:id` | 拒否・期限切れ・収録検出・背面 |
| `PUT /v1/pairings/:id` | 確定後。`tokenHash` を登録 |
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
| 片側のタップだけでペア確定 | 映像の再生や遠隔の片側操作で足りてしまう。双方 LA の重なりが要る |
| SAS や録画フレームを confirm の材料にする | 両方の画面が撮られていれば第三者でも再現できる |

将来足してよいもの: フレンドリな LAN、APNs 起こし、PRF wrapping、`resume` など追加 `op`、完全レプリカ。v1 のエンベロープを壊さない範囲で。

---

## 実装順（同期側）

1. リレー（Hono + DO）とエンベロープの契約テスト
2. iOS: Keychain、オファー QR、Face ID、双方 confirm、snap / cmd / ack

購読者 UI は [14](14-mac-companion-ux.md) が固まってから。いまのリポジトリではゲートもサーバも足さない。
