必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)、[docs/04-architecture.md](../04-architecture.md)、[docs/08-current-status.md](../08-current-status.md)

## 環境

**Mac + Xcode 必須。** iOS Simulator / 実機。Linux Cloud Agent に投げない。

## 触ってよいパス

- `Todo train/` の Settings、App 起動、SessionManager のリモート cmd 適用
- `Packages/TodoTrainSync` は読む。API が足りなければ SYNC-2 に戻す（この PR でパッケージを肥大化させない）

禁止: macOS ターゲット新設、Hub のマルス体験の再設計、CloudKit `isConfigured = true`、Widget の真実源化。

## 目的

iPhone が本尊としてリレーに乗る。

1. 設定「Mac と連携」: 画面を Mac に向けるセルフィー一動作（13）。収録 / スクショでオファー破棄。読めたら端末を戻して Face ID
2. `ScenePhase.active` と発車・停車・延長・到着で snap を置く
3. active 中 WS。ポーリングしない
4. cmd `pause` を復号し、open `WorkSession` と `sessionId` が一致したら `SessionManager` で停車。ack を返す。停車上限などは既存エラーを ack に載せる
5. ベル / LA は既存 `boardedDeviceID` のまま

リレー URL は inf.plist / xcconfig の非秘密（pairing 秘密は Keychain）。デフォルトはローカル wrangler。

## 完了条件

- [ ] シミュレータでペアリング画面が出せる（相手 Mac が無くても QR + 前面カメラ起動）
- [ ] 停車 cmd の適用と ack が単体または結合で説明できる
- [ ] CloudKit ゲートは false のまま
- [ ] PR に Mac 検証チェックリスト（セルフィーは実機）

## ブランチ

`cursor/sync-3-ios-…`。SYNC-2 マージ後。結合は SYNC-1 の worker。
