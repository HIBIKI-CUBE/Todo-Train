必読: [docs/15-agent-work-plan.md](../15-agent-work-plan.md)、[docs/13-sync-mac-companion.md](../13-sync-mac-companion.md)、[docs/04-architecture.md](../04-architecture.md)

## 状態

**今は振らない。** Linux では完了できない。手が空いて Mac を開けるまで置いておく。ロジックは SYNC-2 / SYNC-5 済みが前提。

## 環境

Mac + Xcode。Linux Cloud Agent に投げない。蓋を開けたまま `cursor worker start` があればセルフホスト可。

## 触ってよいパス

- `Todo train/` の Settings、起動、SessionManager から `RemotePauseEvaluating` を呼ぶ配線
- xcodeproj への `TodoTrainSync` 参照

禁止: macOS ターゲット、CloudKit on、停車ロジックの再実装（パッケージを呼べ）。

## 目的

セルフィー UI と `ScenePhase` での snap/cmd。中身の判定はパッケージ任せ。

## 完了条件

- [ ] 実機またはシミュレータでペアリング画面
- [ ] 停車 cmd → 既存 SessionManager.pause
- [ ] CloudKit は false
- [ ] Mac 検証チェックリスト（セルフィーは実機）

## ブランチ

`cursor/sync-3-ios-…`。SYNC-5 のあとが望ましい。
