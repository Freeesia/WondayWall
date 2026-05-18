# WondayWall — アプリ固有の実装方針

このファイルは **全プラットフォーム共通の実装方針（常時読み込み）** の正本です。

## プロダクト方針（共通）

- WondayWall は、ユーザーの予定や興味に基づいて壁紙を生成するアプリ。
- 実装対象は複数プラットフォーム（.NET/Windows、iOS、Android）。
- 生成処理の中心は `GenerationCoordinator` に集約し、ビジネスロジックの重複を避ける。
- 設計は「完成の速さ」「修正のしやすさ」「構成の分かりやすさ」を優先する。

## 共通実装ルール

- コメントは日本語で記載する。
- 必要になるまで過剰な抽象化を行わない。
- サービスインターフェースは、複数実装が必要になった時点で導入する。
- 変更は最小限にし、関連しない箇所は触らない。

## Copilot Instructions の分割

- **常時読み込み**: この `AGENTS.md`（全プラットフォーム共通）
- **条件付き読み込み**: プラットフォーム別 instruction files

### .NET版（Win版）

- `.github/instructions/dotnet-win.instructions.md`
- 詳細仕様: `/dev.md`

### iOS版

- `.github/instructions/ios.instructions.md`
- 詳細仕様: `/dev_ios.md`

### Android版

- `.github/instructions/android.instructions.md`
- 詳細仕様: `/dev_android.md`
