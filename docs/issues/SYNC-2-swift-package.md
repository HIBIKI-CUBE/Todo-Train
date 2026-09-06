必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)、`sync/contract/`（SYNC-0 マージ後）

## 環境

Swift。UI も SessionManager も触らない。Linux では CryptoKit が無いので、**純関数とエンコードのテストを優先**。実 Keychain / LocalAuthentication は `#if os` で分け、必須検証は Mac 向けチェックリストに回す。

## 触ってよいパス

- `Packages/TodoTrainSync/**` のみ（このチケットでパッケージを作る）
- アプリからリンクするための `Todo train.xcodeproj` の **パッケージ参照追加だけ** は可。画面・モデル・SessionManager は禁止

読んでよい: `sync/contract/**`、docs/13  
禁止: `sync/worker/**` の実装変更、Hub/Focus、CloudKit フラグ。

## 目的

iOS と Mac が同じコードをリンクする。ここが型安全の芯。

含める:

- HKDF / AES-GCM エンベロープ（AAD は 13 どおり）
- snap / cmd / ack の Codable（黄金 JSON と round-trip）
- Pairing URL の parse / build
- リレー client プロトコル（HTTP + WS）。実装は URLSession。base URL は注入
- Keychain と LocalAuthentication は protocol 越し。テストは fake

含めない: SwiftUI、QR 描画、カメラ、メニューバー、`SessionManager`。

カメラ同時交換の **状態機械**（両 QR を出す → 両方読めた → bind → 向きを戻して LA）は UI 無しでテスト可能な型として置いてよい。

## 完了条件

- [ ] `sync/contract` の黄金 JSON を Swift テストが読む
- [ ] Worker を起動しなくても client の encode/decode が通る
- [ ] UI ファイルが無い

## ブランチ

`cursor/sync-2-swift-package-…`。SYNC-0 のあと。SYNC-1 と並列可。
