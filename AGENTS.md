# Todo train — Agent Guide

このリポジトリで作業する AI / 人間向けの入口です。プロダクト決定・用語・技術方針はすべて `docs/` に集約しています。

## 必読（着手前）

1. [docs/README.md](docs/README.md) — ドキュメント索引
2. [docs/01-vision.md](docs/01-vision.md) — 哲学・誰のためか
3. [docs/02-requirements.md](docs/02-requirements.md) — 確定要件・却下事項
4. [docs/03-terminology.md](docs/03-terminology.md) — UI / ドメイン用語（勝手に言い換えない）
5. [docs/08-current-status.md](docs/08-current-status.md) — **現状の実装マップ**

実装・設計変更時は追加で:

6. [docs/04-architecture.md](docs/04-architecture.md) — SessionManager / SwiftData / 運行
7. [docs/05-ux-flows.md](docs/05-ux-flows.md) — 画面とフロー
8. [docs/06-roadmap.md](docs/06-roadmap.md) — MVP / v1 / v2 スコープ
9. [docs/07-research.md](docs/07-research.md) — 根拠・Live Activity 制限
10. [docs/11-v2-alarmkit-setup.md](docs/11-v2-alarmkit-setup.md) — Widget / LA / AlarmKit 配線・検証
11. [docs/12-ui-design.md](docs/12-ui-design.md) — UI 方針
12. [docs/13-sync-mac-companion.md](docs/13-sync-mac-companion.md) — 同期構成（土管。確定）
13. [docs/14-mac-companion-ux.md](docs/14-mac-companion-ux.md) — Mac コンパニオン体験（確認待ち。実装は提案値）
14. [docs/15-agent-work-plan.md](docs/15-agent-work-plan.md) — 同期のチケット切り分け。自分の `docs/issues/SYNC-*` 以外のパスを触らない

## 作業時の原則

- **コーチではなく道具**。質問ウィザードや説教 UI を増やさない。
- **掃き出し摩擦を最小化**（FAB → 即キーボード）。
- **定時の喜びは瞬間だけ**。まず到着を祝う。早着はいい結果。ストリーク・点数・定時率を足さない。超過で案内を取り下げない。
- モデル名は **`Ticket`**（Swift の `Task` と衝突するため）。
- 走行中セッションの真実源は **`WorkSession`（`endedAt == nil`）+ `SessionManager.reconcile()`**。タイマーは Date ベース。
- 同一切符の大幅書き換えはしない。残りは **途中下車 → 乗り継ぎ（新切符）**。
- Live Activity は **発車中のみ**（全日運行 LA は不可。詳細は `07-research.md`）。

## Cloud Agent / Linux 向け注意

- **iOS Simulator / 本格的な `xcodebuild test` は期待しない。**
- 純関数化 + `Todo trainTests` へのテスト追加を優先。
- Live Activity / Widget / 通知 / PCC の実行確認は PR の **Needs Mac verification** に委ねる。
- PR 本文に Mac 検証チェックリストを載せる（[11-v2-alarmkit-setup.md](docs/11-v2-alarmkit-setup.md) §6 参照）。
- 同期: Linux 向きは SYNC-0 / SYNC-1（と SYNC-2 の純関数）。SYNC-3 / SYNC-4 は Mac + Xcode。切り分けは [docs/15-agent-work-plan.md](docs/15-agent-work-plan.md)

## ブランチ

現在の開発ブランチは `develop` を想定。
