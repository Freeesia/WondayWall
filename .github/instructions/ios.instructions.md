---
applyTo: "WondayWall.iOS/**"
---

# iOS版実装ルール

- iOS 実装の詳細は `/dev_ios.md` を正本として従う。
- 生成処理は `GenerationCoordinator` に集約する。
- 定期実行は `BGProcessingTask` 前提で設計し、厳密な時刻実行保証を前提にしない。
- iOS では通常アプリから壁紙の直接適用は行わず、保存・共有・設定手順表示を基本とする。
