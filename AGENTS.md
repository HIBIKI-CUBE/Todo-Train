# Todo train — Agent Guide

このリポジトリで作業する AI / 人間向けの入口です。プロダクト決定・用語・技術方針はすべて `docs/` に集約しています。

## 必読（着手前）

1. [docs/README.md](docs/README.md) — ドキュメント索引
2. [docs/01-vision.md](docs/01-vision.md) — 哲学・誰のためか
3. [docs/02-requirements.md](docs/02-requirements.md) — 確定要件・却下事項
4. [docs/03-terminology.md](docs/03-terminology.md) — UI / ドメイン用語（勝手に言い換えない）

実装・設計変更時は追加で:

5. [docs/04-architecture.md](docs/04-architecture.md) — SessionManager / SwiftData / 運行
6. [docs/05-ux-flows.md](docs/05-ux-flows.md) — 画面とフロー
7. [docs/06-roadmap.md](docs/06-roadmap.md) — MVP / v1 / v2 スコープ
8. [docs/07-research.md](docs/07-research.md) — 根拠・Live Activity 制限

## 作業時の原則

- **コーチではなく道具**。質問ウィザードや説教 UI を増やさない。
- **掃き出し摩擦を最小化**（FAB → 即キーボード）。
- モデル名は **`Ticket`**（Swift の `Task` と衝突するため）。
- 走行中セッションの真実源は **`WorkSession`（`endedAt == nil`）+ `SessionManager.reconcile()`**。タイマーは Date ベース。
- 同一切符の大幅書き換えはしない。残りは **途中下車 → 乗り継ぎ（新切符）**。
- Live Activity は **発車中のみ**（全日運行 LA は不可。詳細は `07-research.md`）。

## ブランチ

現在の開発ブランチは `develop` を想定。
