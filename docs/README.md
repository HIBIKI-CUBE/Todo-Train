# Todo train ドキュメント索引

計画会話（2026-08-11）と実装初期状態を突合した設計資料です。  
別 Agent / 将来の自分向けの **単一の参照元** として使ってください。

| ファイル | 内容 |
|----------|------|
| [01-vision.md](01-vision.md) | プロダクトビジョン・哲学 |
| [02-requirements.md](02-requirements.md) | 確定要件・却下オプション・未決 |
| [03-terminology.md](03-terminology.md) | 列車メタファ用語表 |
| [04-architecture.md](04-architecture.md) | 技術スタック・データモデル・SessionManager |
| [05-ux-flows.md](05-ux-flows.md) | 画面・操作フロー |
| [06-roadmap.md](06-roadmap.md) | フェーズ別スコープ・実装順 |
| [07-research.md](07-research.md) | 研究根拠・Live Activity / AlarmKit 制限 |

ルートの [AGENTS.md](../AGENTS.md) が作業開始時の短い入口です。

## ステータス（ドキュメント作成時点）

- ターゲット: **iPhone 15 Pro Max / iOS 27**
- スタック: **SwiftUI + SwiftData**
- ドメイン型: **`Ticket`**, **`ServiceDay`**, **`WorkSession`**, **`TaskLineage`**, **`Tag`**
- コア実装は `develop` 上で進行中（SessionManager / Hub / Focus / History 等）
- 計画は会話で確定。詳細な根拠と制約は各ファイルを参照
