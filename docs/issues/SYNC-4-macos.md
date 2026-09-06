必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)、[docs/14-mac-companion-ux.md](../14-mac-companion-ux.md)

## 環境

**Mac + Xcode 必須。** Linux Cloud Agent に投げない。

## 触ってよいパス

- macOS ターゲット新設（メニューバー accessory）
- `Packages/TodoTrainSync` の利用
- ペアリングの Mac 側 UI（大きな QR + ウェブカメラプレビュー）

禁止: iOS Hub/Focus/Widget の改修、切符全件のローカル DB、再開・到着・延長 UI。

## 画面のデフォルト（14 の提案。未確認でもこれで進む）

- Dock なしメニューバー。乗務なしはアイコンのみ
- 操作は停車のみ。楽観的に走行を止めない。「iPhone に送った」
- 超過は表示のみ（3 択なし）
- ログイン時起動 ON
- 主経路はセルフィー同時交換（Mac カメラ必須）。カメラ無しはこのチケットでやらなくてよい

## 目的

1. 未ペア: QR + カメラ枠。「iPhone の画面をこちらに向ける」
2. ペア後: タイトル、Date ベースの残り、停車 → cmd。SwiftData を持たない
3. ack 失敗は一行（停車上限など）

## 完了条件

- [ ] メニューバー extra が起動する
- [ ] ダミー snap で残りが Date 計算される
- [ ] 実リレー結合は SYNC-1 + SYNC-3 待ちでも、パッケージ経由の cmd 組み立てがテストできる
- [ ] PR に Mac 検証チェックリスト

## ブランチ

`cursor/sync-4-macos-…`。SYNC-2 マージ後。SYNC-3 と並列可。
