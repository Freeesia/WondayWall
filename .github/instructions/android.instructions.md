---
applyTo: "WondayWall.Android/**"
---

# Android版 実装ルール

## 参照先

- 詳細仕様の正本は `/dev_android.md`。
- 実装構成は `WondayWall.Android/app/src/main/kotlin/com/studiofreesia/wondaywall/` 配下を基準にする。

## プロジェクト/実装方針

- 初期版 DI は `App.kt` の手動 DI を維持する（Hilt 前提にしない）。
- 生成フローは `GenerationCoordinator` に集約する。
- 定期実行は `TaskSchedulerService` に集約し、内部実装として WorkManager を使う。
- 壁紙処理は `WallpaperService` に集約する。

## 設定モデルの重要ルール

- `AppConfig` は Windows 側と主要フィールド名を揃える。
- スケジュールは `schedule: UpdateSchedule` で管理する。
- 通知設定は `showNotification` の単一フラグで管理する。
- `runsPerDay` や `notifyOnSuccess` / `notifyOnFailure` のような旧構成を再導入しない。

## セキュリティ

- API キーは `AppConfigService` で Tink（AES256-GCM, Android Keystore）により暗号化保存する。
- DataStore には API キーを平文保存しない（設定 JSON から除外する）。
- `AeadConfig.register()` は `App.onCreate()` の 1 回呼び出しを維持する。

## スケジューリング

- `TaskSchedulerService` のスロット計算ロジック（4:00 基準、週次/日次）を維持する。
- `GenerationWorker` は `GenerationCoordinator` を通して処理し、直接サービスを分散呼び出ししない。
- 自動生成無効時は既存 Work を確実にキャンセルする。

## 変更時の注意点

- `App.kt` のサービス初期化順を崩さない（依存順を維持）。
- 低電力・ネットワーク条件の判定を無断で緩めない。
- 壁紙適用失敗時も履歴と生成画像を保持し、手動適用にフォールバック可能な状態を保つ。
