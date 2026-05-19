---
applyTo: "WondayWall/**/*.cs"
---

# .NET版 実装ルール（現行実装は Windows 向け）

## 参照先

- 詳細仕様の正本は `/dev.md`。
- 既存実装の全体方針は `/AGENTS.md`。

## 実装方針

- 現行アプリは `net10.0-windows` + WPF 実装だが、.NET 層の設計は将来のマルチプラットフォーム展開を妨げないように保つ。
- 生成フローの業務ロジックは `GenerationCoordinator` に集約し、GUI/CLI 間で重複させない。
- サービスは原則具体クラス参照で実装し、複数実装が必要になった時点で interface を導入する。

## アーキテクチャ上の必須ルール

- `Program.cs` のハイブリッド構成（GUI + CLI）を維持する。
- CLI は `ConsoleAppFramework`、GUI は `KamishibaiApplication<App, MainWindow>` を使う構成を維持する。
- `ConfigureCommonServices` の依存関係順を崩さない。
- `GenerationCoordinator` の多重実行防止（`SemaphoreSlim`）を維持する。

## DI / MVVM / UI

- サービスは `AddSingleton`、View / ViewModel は `AddTransient` を維持する。
- MVVM は CommunityToolkit.Mvvm（`[ObservableProperty]`, `[RelayCommand]`）を前提とする。
- UI は WPF-UI コンポーネント優先で実装する。

## 設定・保存・非同期

- 設定・履歴・OAuth トークン・生成画像は `%LocalAppData%/StudioFreesia/WondayWall/` 配下を利用する。
- 履歴は `history.json` で管理し、安易に DB 化しない。
- 長時間処理は `async Task` で実装し、UI スレッドをブロックしない。

## 変更時の注意点

- `<StartupObject>WondayWall.Program</StartupObject>` を削除しない（CLI 起動が壊れる）。
- `<EnableWindowsTargeting>true</EnableWindowsTargeting>` を削除しない（Linux CI 互換）。
- カレンダー/ニュースの入力件数制限を無断で緩めない（API 制約に影響）。
