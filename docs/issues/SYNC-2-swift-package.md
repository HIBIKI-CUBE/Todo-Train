必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)、`sync/contract/`（SYNC-0 マージ後）

## 環境

**Linux Cloud Agent。** `swift test` が完了条件。Xcode / シミュレータ / 実機は使わない。CryptoKit は使わず [swift-crypto](https://github.com/apple/swift-crypto)。

## 触ってよいパス

- `Packages/TodoTrainSync/**` のみ（このチケットで作る）

禁止: `Todo train.xcodeproj`、`sync/worker/**` の変更、SwiftUI、カメラ、Keychain 実物、Hub/Focus。

## 目的

iOS と Mac が後で同じコードをリンクする。今は Linux で契約を閉じる。

含める:

- HKDF / AES-GCM エンベロープ（13 の info 文字列）
- snap / cmd / ack の Codable。`sync/contract` の黄金 JSON と round-trip
- Pairing URL の parse / build
- HTTP + WS client。base URL 注入。Keychain / LA / カメラは protocol + fake
- ペアリング状態機械（両 QR 提示 → 両方読めた → bind → LA）。光学入力はテストから文字列で渡す
- `RemotePauseEvaluating`: open sessionId・停車数・上限・cmd → 適用 / mismatch / pauseLimitReached / noActiveService。SessionManager を import しない
- `MenuBarPresentation`: snap + now → 残り（Date 計算）・超過・停車可否・送信中。14 の提案値

含めない: SwiftUI、QR 描画、xcodeproj 参照。

## 完了条件

- [ ] パッケージ根で `swift test` が Linux で通る
- [ ] 黄金 JSON の round-trip がある
- [ ] 停車判定とメニューバー表示のテストがある
- [ ] pbxproj が dirty でない

## ブランチ

`cursor/sync-2-swift-package-…`。SYNC-0 のあと。SYNC-1 と並列可。
