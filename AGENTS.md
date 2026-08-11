# Todo train — Agent Guide

このリポジトリで作業する AI / 人間向けの入口です。プロダクト決定・用語・技術方針はすべて `docs/` に集約しています。

## 必読（着手前）

1. [docs/README.md](docs/README.md) — ドキュメント索引
2. [docs/01-vision.md](docs/01-vision.md) — 哲学・誰のためか
3. [docs/02-requirements.md](docs/02-requirements.md) — 確定要件・却下事項
4. [docs/03-terminology.md](docs/03-terminology.md) — UI / ドメイン用語（勝手に言い換えない）

### いまのフェーズが v1 のとき（Cloud Agent 含む）

5. [docs/08-current-status.md](docs/08-current-status.md) — MVP 完了マップ
6. [docs/09-v1-implementation.md](docs/09-v1-implementation.md) — **実装指示書（スコープ・WP・Linux 制約・受入）**

実装・設計変更時は追加で:

7. [docs/04-architecture.md](docs/04-architecture.md) — SessionManager / SwiftData / 運行
8. [docs/05-ux-flows.md](docs/05-ux-flows.md) — 画面とフロー
9. [docs/06-roadmap.md](docs/06-roadmap.md) — MVP / v1 / v2 スコープ
10. [docs/07-research.md](docs/07-research.md) — 根拠・Live Activity 制限

## 作業時の原則

- **コーチではなく道具**。質問ウィザードや説教 UI を増やさない。
- **掃き出し摩擦を最小化**（FAB → 即キーボード）。
- モデル名は **`Ticket`**（Swift の `Task` と衝突するため）。
- 走行中セッションの真実源は **`WorkSession`（`endedAt == nil`）+ `SessionManager.reconcile()`**。タイマーは Date ベース。
- 同一切符の大幅書き換えはしない。残りは **途中下車 → 乗り継ぎ（新切符）**。
- Live Activity は **発車中のみ**（全日運行 LA は不可。詳細は `07-research.md`）。

## Cloud Agent / Linux 向け注意

- **iOS Simulator / 本格的な `xcodebuild test` は期待しない。**
- 純関数化 + `Todo trainTests` へのテスト追加を優先。
- Live Activity / Widget / 通知 / PCC の実行確認は PR の **Needs Mac verification** に委ねる。
- 詳細は [docs/09-v1-implementation.md](docs/09-v1-implementation.md) §0 と §7。

## ブランチ

現在の開発ブランチは `develop` を想定。
