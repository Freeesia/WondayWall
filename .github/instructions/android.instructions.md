---
applyTo: "WondayWall.Android/**"
---

# Android版実装ルール

- Android 実装の詳細は `/dev_android.md` を正本として従う。
- 生成処理は `GenerationCoordinator` に集約する。
- 定期実行は `TaskSchedulerService` に集約し、内部実装に WorkManager を使う。
- 壁紙適用は `WallpaperService` に集約し、`WallpaperManager` を利用する。
