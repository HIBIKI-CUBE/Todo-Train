必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)、[docs/14-mac-companion-ux.md](../14-mac-companion-ux.md)

## 状態

**コードは PR。** 実機のカメラ / Touch ID / メニューバー見た目は [16-wakeup-checklist.md](../16-wakeup-checklist.md)。Issue: https://github.com/HIBIKI-CUBE/Todo-Train/issues/38

## 環境

Mac + Xcode。Linux Cloud Agent に投げない。

## 触ってよいパス

- macOS ターゲット（メニューバー accessory）
- ウェブカメラ枠 + QR 表示
- `MenuBarPresentation` の利用

禁止: Hub 移植、停車判定の再実装、カメラ無しフォールバック（このチケットではやらなくてよい）。

## 画面

14 の提案値。Dock なし、停車のみ、超過は表示だけ。

## 完了条件

- [ ] メニューバー extra が起動する
- [ ] パッケージの表示状態を描いている
- [ ] Mac 検証チェックリスト

## ブランチ

`cursor/sync-4-macos-…`。SYNC-2（と結合するなら 5）のあと。
