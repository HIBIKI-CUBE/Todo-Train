必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)、SYNC-1 と SYNC-2 のマージ済みコード、`sync/contract/`

## 環境

**Linux Cloud Agent。** Node（wrangler / miniflare）と `swift test`。Xcode 禁止。人間の Mac 起動は不要。

## 触ってよいパス

- `sync/e2e/**` のみ（このチケットで作る）

読んでよい: `sync/worker`、`Packages/TodoTrainSync`、`sync/contract`  
禁止: それらの本番コードの大きな書き換え。足りない API は 1 または 2 に戻す。

## 目的

暗号化クライアントがローカル Worker と往復する。画面も生体も無い。LA は fake で即成功。

少なくとも 1 本:

1. テスト鍵でオファー作成 → 双方の光学文字列を注入 → bind → 双方 confirm HMAC
2. iPhone 役が snap を暗号化して PUT
3. Mac 役が GET/WS で復号し、タイトルと残り計算ができる
4. pause cmd を置き、評価関数が applied を返し、ack が戻る
5. 片側の光学だけ、または confirm が片側だけ、では pairing が確定しない

Worker は ciphertext を JSON.parse しない、をログまたはテストで確認する。

## 完了条件

- [ ] `sync/e2e` の手順（README + コマンド）が Linux で終端 0
- [ ] 平文タイトルが Worker ログに出ない
- [ ] 人間の操作手順が無い

## ブランチ

`cursor/sync-5-linux-e2e-…`。SYNC-1 と SYNC-2 が `develop` に入ってから。
