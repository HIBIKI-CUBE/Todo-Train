# Todo train ドキュメント索引

計画会話（2026-08-11）と実装（Sprint 1–10 / MVP 完了）を突合した設計資料です。  
別 Agent / Cloud Agent / 将来の自分向けの **単一の参照元** として使ってください。

| ファイル | 内容 |
|----------|------|
| [01-vision.md](01-vision.md) | プロダクトビジョン・哲学 |
| [02-requirements.md](02-requirements.md) | 確定要件・却下オプション・未決 |
| [03-terminology.md](03-terminology.md) | 列車メタファ用語表 |
| [04-architecture.md](04-architecture.md) | 技術スタック・データモデル・SessionManager |
| [05-ux-flows.md](05-ux-flows.md) | 画面・操作フロー |
| [06-roadmap.md](06-roadmap.md) | フェーズ別スコープ・実装順 |
| [07-research.md](07-research.md) | 研究根拠・Live Activity / AlarmKit 制限 |
| [08-current-status.md](08-current-status.md) | **MVP 完了時点の実装マップ** |
| [09-v1-implementation.md](09-v1-implementation.md) | **v1 一括実装ハンドオフ（Cloud Agent 向け）** |
| [10-live-activity-setup.md](10-live-activity-setup.md) | Live Activity Xcode セットアップ |
| [11-v2-alarmkit-setup.md](11-v2-alarmkit-setup.md) | AlarmKit / StandBy セットアップ（v2） |
| [12-ui-design.md](12-ui-design.md) | UI / ビジュアル方針（列車テーマ） |

ルートの [AGENTS.md](../AGENTS.md) が作業開始時の短い入口です。

## いま読む順番（v1 実装 Agent）

1. [AGENTS.md](../AGENTS.md)
2. [08-current-status.md](08-current-status.md)
3. [09-v1-implementation.md](09-v1-implementation.md) ← 作業指示の本体
4. 用語・要件で迷ったら [03](03-terminology.md) / [02](02-requirements.md)

## ステータス

- ターゲット: **iPhone 15 Pro Max / iOS 27**
- スタック: **SwiftUI + SwiftData**
- **MVP: 完了**（Sprint 1–10）
- **次: v1**（履歴検索・並べ替えビュー・Settings・LA/Widget 等）
