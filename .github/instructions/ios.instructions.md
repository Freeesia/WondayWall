---
applyTo: "WondayWall.iOS/**"
---

# iOS版 実装ルール

## 参照先

- 詳細仕様の正本は `/dev_ios.md`。
- プロジェクト固有情報は `WondayWall.iOS/README.md` も参照する。

## プロジェクト構成

- iOS プロジェクトは `project.yml` を正本として XcodeGen で生成する。
- `WondayWall.xcodeproj` は生成物として扱い、手編集を前提にしない。
- サービスは `AppEnvironment` で組み立てる。

## 実装方針

- 生成フローは `GenerationCoordinator`（actor）に集約し、多重実行を防止する。
- 手動生成、起動時補完、BG 実行でロジックを重複させない。
- スケジュール処理は `BackgroundTaskService` に集約し、`BGProcessingTask` を使う。
- 手動生成中のバックグラウンド移行は `ForegroundBackgroundTaskService` で扱う。

## iOS 固有制約

- 通常アプリから壁紙の直接適用は行わない。
- 壁紙関連は `WallpaperService` に集約し、写真保存・共有・設定手順表示を提供する。
- `BGProcessingTaskRequest.earliestBeginDate` は「その時刻より前に実行しない」目安として扱う（厳密実行を前提にしない）。

## サービスと責務

- `AppConfigService`: 設定保存
- `ContextService`: カレンダー + RSS からコンテキスト構築
- `GoogleAiService`: Gemini 呼び出しと画像生成
- `HistoryService`: 履歴保存
- `NotificationService`: 成功/失敗通知
- `GenerationCoordinator`: 上記を束ねる実行オーケストレーター

## 変更時の注意点

- `BackgroundTaskService.taskIdentifier` と Info.plist の許可識別子を不整合にしない。
- 通知処理は `AppDelegate` の `UNUserNotificationCenterDelegate` 設定を崩さない。
- 失敗時は履歴保存を必ず維持し、次回再試行可能な状態を保つ。
