# 13 — 同期構成（確定）

最終更新: 2026-09-06。土管・暗号・ペアリング契約。**画面の話はしない。**  
Mac の体験は別紙 [14-mac-companion-ux.md](14-mac-companion-ux.md)（確認待ち）。

この PR ではアプリも Worker も足さない。実装は [15-agent-work-plan.md](15-agent-work-plan.md) のチケットへ。

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
| 認証 | アカウントなし。画面を Mac に向ける一動作で双方の公開鍵を交換（iPhone はセルフィー）。数字照合は人に頼らない。双方 LA は本人確認 |

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

DH の共有秘密・HKDF の出力・confirm の HMAC も画面に出さない。照合数字は **人の防御に使わない**（見ない前提）。

### 同時交換（一動作）

iPhone の画面と前面カメラは同じ向き。画面を机の Mac に向けると:

- Mac のウェブカメラが iPhone の QR を読む
- iPhone のセルフィーが Mac の QR を読む

裏カメラに持ち替えて二度読む、は主経路にしない。両方の QR は最初から同時に出しておく。秘密ではない。

```
todotrain://pair?p=<pairingId>&o=<offerId>&x=<iPhone_eph_pub_b64u>
todotrain://pair-mac?s=<macSession>&y=<Mac_eph_pub_b64u>
```

リレーは、**両方の光学読取が揃うまで** 相手を固定しない。iPhone が `y` を読めただけでは足りない。Mac 側も `x` を読めたことを報告する。

### 手順

1. 双方が一時鍵を作り、QR を同時に出す。iPhone は前面カメラを起動する
2. 利用者が iPhone の画面を Mac に向ける。成功は haptic と、Mac 画面のプレビュー枠（利用者は端末の背面を見ているので、狙いは Mac 側で見せる）
3. 両方読めたらリレーに `bind`。**まだ Keychain に書かない**
4. iPhone を自分に戻して Face ID / パスコード（セルフィー中は顔が画面側に無い）
5. Mac は Touch ID / パスワード。双方が数秒以内
6. 確定。オファーは捨てる
7. 拒否・期限切れ・背面・収録検出: 破棄

録画を見ている他人の画面に QR が出ても、iPhone 本体のセルフィーは机の Mac を見ている。机に他人の QR は無い。Mac のウェブカメラも、前にある実機の QR しか読まない。

他人が先に映像の QR を読んでも、iPhone に「許可しますか」は出ない。光学が揃うまで Face ID しない。

Mac にカメラが無いときだけ、貼り付け + 逐次読取に落とす（主経路ではない）。

### 人は照合数字を見ない

Bluetooth の数値比較と同じで、一致確認は見ない。見ないなら防御ではない。「どの Mac か」はセルフィーが机の画面を読む行為。「本人か」は Face ID / Touch ID。セルフィー中に Face ID はできないので、読取と本人確認は同じ向きにしない。

点滅 QR で秘密を分割しない。録画で全フレームが残る。

リカバリを出すなら書き写し用の語または hex だけ。**QR にしない。** 収録中は隠す。ウィザードで強制しない。書き写しはペア確定後の任意。

WebAuthn PRF は主鍵にしない。Face ID は確定の本人確認と Keychain 保護に使う。

改ざん: AES-GCM。ロールバックは `rev` 単調増加。サーバ侵害の残りは削除 DoS。許容する。

---

## 暗号

HKDF-SHA256 の入力は、許可後は `masterKey`。ペアリング中は DH 共有秘密。サーバに渡すのは ciphertext と、オファー用の一時公開鍵だけ。

| 派生鍵 | info | 用途 |
|--------|------|------|
| `enc` | `todotrain/v1/enc` | AES-256-GCM |
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
| `POST /v1/offers/:id/bind` | 双方の光学読取が揃ったあと。片方のカメラだけは不可 |
| `POST /v1/offers/:id/confirm-iphone` | iPhone。bind 後、LA 成功後の HMAC |
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

認証: snap / cmd / ack / WS は Bearer `writeToken`（確定後）。オファー面は TTL だけ。QR を片側が読んだだけでは bind しない。

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
| 照合数字を人の防御にする | 見ない。Face ID が攻撃者リクエストのゴム印になる |
| 最初の QR を読んだだけでリレーに相手を固定する | 録画からの先着が「許可しますか」になる |
| 裏カメラへの持ち替えを主経路にする | セルフィー一動作で足りる。カメラ無し Mac だけ逐次に落とす |

将来足してよいもの: フレンドリな LAN、APNs 起こし、PRF wrapping、`resume` など追加 `op`、完全レプリカ。v1 のエンベロープを壊さない範囲で。

---

## 実装順（同期側）

1. リレー（Hono + DO）とエンベロープの契約テスト
2. iOS: Keychain、セルフィー同時交換、Face ID、双方 confirm、snap / cmd / ack

購読者 UI は [14](14-mac-companion-ux.md) が固まってから。いまのリポジトリではゲートもサーバも足さない。
