# WondayWall — Instructions

WondayWall は、ユーザーの予定や興味に基づいて壁紙を自動生成する Windows 向け .NET 10 WPF アプリ。
詳細は [概要.md](/概要.md) および [dev.md](/dev.md) を参照。

## ビルドと実行

```powershell
# プロジェクトルートから
cd WondayWall
dotnet build

# GUI 起動
WondayWall.exe

# CLI モード（Task Scheduler から呼ぶパターン）
WondayWall.exe run-once    # 1回だけ生成して終了
WondayWall.exe generate    # 即時生成
WondayWall.exe check-calendar
WondayWall.exe check-news
WondayWall.exe check-google-ai
```

環境要件:
- Windows OS のみ（`net10.0-windows`; WPF は Windows 専用）
- .NET 10 SDK
- Google Cloud プロジェクト（Calendar API + GenAI API 有効化済み）
- `EnableWindowsTargeting=true` は Linux CI ビルド用に csproj に設定済み。削除しないこと。

## アーキテクチャ

### ハイブリッド GUI/CLI 構成

同一 exe から GUI と CLI を使い分ける設計。常駐アプリにはしない。

```
Program.cs
├─ CLI モード: args[0] が既知コマンドなら ConsoleAppFramework → CliCommands → Services
└─ GUI モード: WpfApplication<App,MainWindow>.CreateBuilder() → DI → WPF 起動
```

### サービス層

| サービス | 責務 |
|---------|------|
| `AppConfigService` | JSON 設定の読み書き（`%AppData%/WondayWall/appsettings.json`） |
| `ContextService` | Google Calendar + RSS フィードからプロンプトコンテキストを構築 |
| `GoogleAiService` | Gemini API で壁紙画像を生成・保存 |
| `WallpaperService` | Win32 API で壁紙を適用 |
| `GenerationCoordinator` | 上記サービスを順次呼び出すオーケストレーター。`SemaphoreSlim(1,1)` で多重実行を防止 |

`GenerationCoordinator` は GUI・CLI 両方から呼ばれる。ビジネスロジックの重複を避けるため変更はここに集約する。

### DI 登録ルール

- サービスはすべて **Singleton** (`AddSingleton`)
- ViewModel・View は **Transient** (`AddTransient`)

## 規約

- コメントは日本語で記載する。

### MVVM

- CommunityToolkit.MVVM を使用。`[ObservableProperty]`・`[RelayCommand]` 属性でボイラープレートを排除。
- サービスインターフェースは設けない（具体クラス直接参照）。複数実装が必要になったときに追加する。
- 現状 ViewModel は `MainWindowViewModel` のみ。単純に保つことを優先。

### UI

- WPF-UI を使用。コントロールは `<ui:FluentWindow>`, `<ui:CardControl>`, `<ui:Button Appearance="Primary">` など WPF-UI のコンポーネントを優先する。
- 標準の WPF コントロールより WPF-UI コントロールを選ぶこと。

### 設定・データ保存

- 設定・履歴・OAuth トークン・生成画像はすべて `%AppData%/WondayWall/` 以下に保存。
- 履歴は `history.json`（JSON ファイル、DB は使わない）。

### 非同期

- 長時間処理は `async Task` コマンド（`AsyncRelayCommand`）で実行。
- 多重実行防止には `SemaphoreSlim` を使う（Mutex は使わない）。

## よくある落とし穴

- **`StartupObject` の削除禁止**: `<StartupObject>WondayWall.Program</StartupObject>` を削除すると WPF デフォルトエントリーポイントになり CLI モードが壊れる。
- **OAuth トークンキャッシュ**: `%AppData%/WondayWall/calendar-token/` に保存。クレデンシャル変更後は手動削除が必要。
- **プロンプトサイズ**: カレンダー・ニュースは各5件に絞って送信。それ以上に増やす場合は GenAI API の制限を確認。
- **`IsGenerating` フラグ**: 生成中はボタンを無効化する設計。`CanExecuteChanged` を忘れずに呼ぶ。
