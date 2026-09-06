# Todo train ドキュメント索引

計画会話（2026-08-11）と実装（MVP → v1 → v2）を突合した設計資料です。  
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
| [08-current-status.md](08-current-status.md) | **現状の実装マップ・テスト手順** |
| [11-v2-alarmkit-setup.md](11-v2-alarmkit-setup.md) | Widget / Live Activity / AlarmKit セットアップ・検証 |
| [12-ui-design.md](12-ui-design.md) | UI / ビジュアル方針（列車テーマ） |
| [13-sync-mac-companion.md](13-sync-mac-companion.md) | Mac 連携の同期検討（CloudKit vs 自前 / ペアリング / E2E）。**未決** |

ルートの [AGENTS.md](../AGENTS.md) が作業開始時の短い入口です。

## いま読む順番（新規 Agent / 変更着手時）

1. [AGENTS.md](../AGENTS.md)
2. [08-current-status.md](08-current-status.md) — いま何があるか
3. 用語・要件で迷ったら [03](03-terminology.md) / [02](02-requirements.md)
4. LA / Widget / AlarmKit を触るなら [11](11-v2-alarmkit-setup.md)
5. UI を触るなら [12](12-ui-design.md)
6. Mac / 同期を触るなら [13](13-sync-mac-companion.md)（経路は未決）

## ステータス

- ターゲット: **iPhone 15 Pro Max / iOS 27**
- スタック: **SwiftUI + SwiftData**
- **MVP / v1 / v2: `develop` にマージ済み**
- **次: CloudKit（WP-I）準備中。Mac 同期の経路は [13](13-sync-mac-companion.md) で検討中（未決）。実 iCloud は有料 Apple Developer Program**
