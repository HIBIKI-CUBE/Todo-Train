# 13 — Mac 連携と同期（検討・未決）

最終更新: 2026-09-06。実装しない。方針が決まるまで CloudKit ゲートは現状維持。

Mac メニューバー（走行中タイトル / 残り / 停車）のために、CloudKit 私有同期と自前ホスト（Hono + Cloudflare Workers）を比べたメモ。要件の芯は **遅延の小さい同期** と **中身がサーバ側から読めないこと**。

## 先に答えてほしいこと

方針がここで分かれる。答えが来るまで実装に入らない。

1. **Mac の主用途**
   - A. 同じ Wi-Fi の机（iPhone はポケット / Focus 中、Mac から停車）
   - B. 外出中の iPhone を、家や別ネットの Mac からも操作したい
   - C. Mac でも Hub / 履歴まで含めた完全レプリカが欲しい
2. **E2E の敵**
   - 自前サーバ（運用者・押収）に見えなければいい。Apple 私有 DB は許容
   - Apple 含め、サーバを持っていても明文が出てはだめ
   - できるだけ見えない方がいいが、停車の速さ・工数のほうが優先

---

## 結論（仮定つき）

**Hono + CFW で ADP 課金を避ける、は成立しない。** iPhone が背面のときに Mac から停車を届けるなら、信頼できる起こし方は APNs で、本番プッシュは有料 Apple Developer Program が要る。CloudKit をやめてもこの壁は残る。

いまの SwiftData 私有 CloudKitは **Apple に対する E2E ではない。** 通信と保管は暗号化されるが鍵は Apple 側。鯖缶相当（Apple / 法執行）では中身が見える。`CKRecord.encryptedValues` は真の E2E だが SwiftData 自動同期は使わない。

推奨の並べ方:

| 条件 | 第一選択 | ADP | 真の E2E | 遅延 |
|------|----------|-----|----------|------|
| 机の同じ LAN が主 | **ローカルペアリング**（Network.framework） | 不要 | トラフィックが家から出ない | 数十 ms |
| インターネット越し + Apple に見えてよい | **いまの CloudKit 計画** | 要 | いいえ | 秒〜十数秒（サイレントプッシュ） |
| インターネット越し + Apple にも見せない | **ペアリング鍵 + 暗号化ブロブ + CF Durable Object** | Push 用に要 | はい（正しく実装すれば） | 前面は WS で即時。背面は APNs 起こし + 取得 |
| ADP 回避が最優先 | LAN ペアリングにスコープを切る。外出先からの停車は「次にアプリを開いたとき」 | 不要 | はい | 背面では遅延を受け入れ |

**アカウントは発行しない。** 1 人・少数端末ならペアリング + リカバリキーが認証より先。WebAuthn PRF は日常の内容暗号の主鍵にしない（リカバリの wrapping に限る）。

「結局 CloudKit」もあり得る。そのときは **E2E（Apple 含む）を要件から外す** と明記する。スキーマ準備は無駄にならない。

---

## 1. いまのコードが前提にしていること

ロードマップの「次」は CloudKit → Mac 最小（走行中の停車）。実装はゲートまで:

- [`CloudKitSync.swift`](../Todo%20train/App/CloudKitSync.swift) — `isConfigured == false` のあいだ `cloudKitDatabase: .none`
- モデルは CloudKit 契約（`@Attribute(.unique)` なし、optional リレーション、String enum）
- `WorkSession.boardedDeviceID` — ベル / LA / 車内放送は発車した端末だけ
- リモート変更フック — `NSPersistentStoreRemoteChange` → `SessionManager.handleRemoteStoreChange()`
- Mac 面・ネットワーキング・Keychain 暗号・ペアリングは未着手

iPhone が本尊。Mac は当初メニューバーの薄い操作面。Hub のマルス体験は iPhone に残す想定（[06-roadmap.md](06-roadmap.md)）。

---

## 2. ADP が買っているもの

有料 Apple Developer Program は CloudKit 専用課金ではない。

| 能力 | 無料 Personal Team | 有料 ADP |
|------|-------------------|----------|
| シミュレータ / 実機デバッグ | 可（証明書 7 日） | 可 |
| SwiftData 私有 CloudKit | 不可（entitlement で署名失敗） | 可 |
| 本番 APNs | 不可 | 可 |
| App Store / TestFlight | 不可 | 可 |
| 同じ LAN の Network.framework | 可 | 可 |
| 自前 HTTPS への URLSession | 可 | 可 |

Mac から「ポケットの iPhone を停車」するとき、サーバを自前にしても **背面の iOS を起こす手段** が要る。前面同士の WebSocket は ADP なしでできる。iOS は背面ソケットをすぐ切る。本番で起こすなら APNs → **ADP が残る。**

だから「CloudKit が嫌だから CFW」は、課金回避にはならない。回避できるのは **背面配信を捨てる**（LAN のみ、または次回起動時に同期）ときだけ。

---

## 3. CloudKit で足りること / 足りないこと

足りる:

- 同一 Apple ID の端末間レプリカ。ペアリング UI なし
- SwiftData のまま。いまの WP-I 準備をそのまま使える
- サイレントプッシュでストア更新。ポーリング不要
- `boardedDeviceID` の他機ベル抑制と相性が良い

足りない:

- **真の E2E。** 私有 DB でも鍵は Apple。Advanced Data Protection の対象一覧に、サードパーティ SwiftData コンテナは入らない
- 遅延の上限保証がない。数秒が普通で、背面だとさらに伸びる
- 競合は属性単位の last-write-wins。リレーションと `sortOrder` は汚れやすい
- サーバ側で「このセッションを停車」のようなコマンド面はない。双方がレコードを書く

E2E を CloudKit 上でやるなら、レコードを不透明な暗号文にする → SwiftData 自動同期の旨味が消え、自前同期と同じ仕事になる。その土管が CloudKit である必然は薄い。

---

## 4. 認証: アカウントよりペアリング

個人利用・端末 2〜3 台が前提なら、メール/パスキーのアカウントはコストだけ先に来る（発行、復旧、セッション、利用規約、サーバ上の個人情報）。

**推奨:** アカウントなし。一度きりのペアリング。

```
iPhone（本尊）                    Mac
  256-bit マスター鍵を生成
  QR = pairingId || 公開情報
       || 鍵そのもの or SPAKE2+ 用の短いコード
        ---------------------->  カメラ / コード入力
  双方 Keychain にマスター鍵
  サーバを使うなら pairingId だけが識別子
```

サーバ認証は「誰のアカウントか」ではなく **このペアリングの鍵を持っているか。** HMAC（時刻 + nonce）か、ペアリング時に登録した端末 Ed25519。サーバーは `pairingId` 以外の個人情報を持たない。

リカバリ: マスター鍵を 24 語または hex で一度だけ出す。両方の端末を失い、紙も無いなら中身は戻らない。E2E ではこれが正常。iCloud に鍵を置くと Apple 依存に戻る。

WebAuthn PRF（passkey から鍵導出）:

- 日常の AES 鍵にしない。PRF の対応差、毎回の assertion、iCloud 同期パスキーだと再び Apple 隣接
- 使える場所: **リカバリ用 wrapping。** マスター鍵は Keychain。新規端末だけパスキーでアンラップ
- Face ID で中身を守るなら、Secure Enclave / Keychain で足りる。WebAuthn を経由しない

---

## 5. 暗号: サーバが缶でも読めない

目標: サーバ（と押収）は ciphertext とメタデータ（`pairingId`、revision、時刻）しか見ない。タイトルも見積もりも乗務結果も平文にしない。

| 層 | 選択 |
|----|------|
| マスター鍵 | 32 bytes。端末 Keychain。サーバに送らない |
| 内容 | AES-GCM。レコードまたは op ごと。AAD に `pairingId` + 型 + id |
| 鍵導出 | HKDF で payload / コマンド / 端末認証を分ける |
| サーバメタ | `pairingId`、`rev`、`deviceId` のハッシュ、サイズ、時刻。タイトルは載せない |
| APNs | 本文は入れない。起こす ping だけ。本体は WS か短い GET |

Mac v1 なら切符全件を暗号化レプリカしなくてよい。暗号化する最小面:

- いまの走行スナップショット（タイトル、残り、phase、`sessionId`）
- コマンド（停車 / 再開）。コマンドも暗号化。サーバは「不透明な envelope が来た」とだけ知る

完全レプリカが要るなら、サーバを SwiftData の正本にしない。端末が復号して既存の `ModelContext` に適用する。サーバは暗号化 op ログ、または暗号化スナップショット + バージョンベクトル。競合は端末側（LWW か、`sortOrder` だけ CRDT）。

---

## 6. 同期の形（ポーリングしない）

「DB を正本にする」と「iPhone がスタート合図だけ出す」は別問題。v1 Mac は後者に近い。

```
                    ┌─ 前面: Hibernatable WebSocket ─
 iPhone ─── 暗号化 ─┤
                    └─ 背面: APNs ping → 短い取得 ──  Durable Object（pairing 1 つ）
 Mac    ─── 暗号化 ─┘                                      ciphertext だけ保持
```

| やり方 | 使うか | 理由 |
|--------|--------|------|
| ポーリング | 使わない | 遅延とバッテリー。要件に反する |
| 前面 WebSocket | 使う（自前同期のとき） | 机の前面同士なら即時。ADP 不要 |
| APNs | インターネット + 背面なら使う | iOS を起こす。ADP 要 |
| CloudKit サイレントプッシュ | CloudKit 経路のとき | ポーリングではない。遅延は秒単位 |
| LAN TCP/QUIC | 机が主なら第一 | サーバも ADP も不要 |
| サーバ側 SwiftData / 正本 DB | 使わない（E2E 時） | 復号できない正本はマージできない |

最適化の芯は差分アルゴリズムより **起こし方。** 走行中スナップショットは小さい。全履歴の CRDT は C（完全レプリカ）になるまで不要。

iPhone を正本にするコマンド面:

1. Mac は暗号化コマンドを DO に置く（または LAN で直接）
2. iPhone が復号し、`SessionManager` で停車する（他機ベル抑制は既存）
3. 新しいスナップショットを暗号化して戻す
4. Mac メニューバーはスナップショットだけ描く。Hub は持たない

「これをスタート」を iPhone 起点にするなら、Mac は購読者。発車の真実はいまどおり open `WorkSession`。

---

## 7. 経路の比較

### 経路 L — 同じ LAN のペアリング

Network.framework（Bonjour）。QR / PIN。TLS か Noise。iPhone が本尊、Mac はリモコン。

- ADP なし、真の E2E（家から出ない）、遅延は最小
- 別ネットワークでは動かない
- iPhone 背面のローカルリスンは OS に殺されやすい。机で Focus 前面、または同じ Wi-Fi で生きているあいだ、が現実的なスコープ
- Mac v1 の「机から停車」と最も合う

### 経路 K — 有料 ADP + SwiftData CloudKit

WP-I のフラグを立て、同じコンテナで Mac を足す。

- 工数が最小。アカウントも暗号も自前にしない
- E2E（Apple 含む）は満たさない
- 遅延はサイレントプッシュ次第
- メニューバー停車は「両方のストアが open session を更新する」になり、コマンド面より競合に弱い。Mac は `endedAt` / `phase` を書く。`boardedDeviceID` でベルは iPhone 側

### 経路 E — ペアリング + E2E + CF Durable Object

Hono は HTTP 面（ペアリング登録、スナップショット POST、コマンド POST）。リアルタイムは DO の WebSocket。R2/KV に ciphertext。

- サーバ缶では読めない、を満たせる
- アカウント不要
- 背面の即時性は APNs → ADP は残る。課金回避にはならない
- 工数は CloudKit より桁で大きい（ペアリング、鍵、競合、起こし、Mac/iOS のバックグラウンド）
- Cloudflare の従量は 1 ユーザーなら無料枠で足りる。高いのは実装

Hono + CFW 自体は経路 E の置き方として妥当。疑問なのは「ADP の代わり」という動機。

---

## 8. 決め方

```
Mac は同じ LAN の机が主？
  yes → 経路 L。CloudKit / CFW は後回し
  no  → 背面でもインターネット越しに停車する？
          no  → 次回前面で同期。ADP なしで経路 E の WS だけも可
          yes → ADP は払う
                 Apple にタイトルが見えてよい？
                   yes → 経路 K（いまの計画）
                   no  → 経路 E（CFW は土管。E2E はクライアント）
```

WebAuthn PRF を主鍵にする案は、どの経路でも第一選択にしない。

---

## 9. やらないこと（このメモの範囲）

- いま `CloudKitSync.isConfigured` を true にしない
- サーバ実装・Mac ターゲットをこの PR で足さない
- JSON エクスポートを同期の代わりにしない（要件 X-07）

未決の 2 問が埋まってから、経路 L / K / E のどれかを [02-requirements.md](02-requirements.md) と [06-roadmap.md](06-roadmap.md) に確定として書く。
