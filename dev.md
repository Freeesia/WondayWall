# WPF 壁紙生成アプリ 実装指針

## 概要

本書は、WPF ベースの壁紙生成アプリの実装指針をまとめたものである。
設計の美しさよりも **完成の速さ、修正のしやすさ、構成の分かりやすさ** を優先する。

本アプリは、ユーザーの予定や関心に応じて画像を生成し、壁紙として適用する。常駐アプリにはせず、**GUI モード** と **CLI モード** を 1 つの exe にまとめたハイブリッド構成を採用する。

---

## アーキテクチャ方針

**常駐しないハイブリッド型**とする。トレイ常駐ではなく、1 つの exe を GUI と CLI の両方で使い分ける。

| モード | 起動方法 | 用途 |
|--------|---------|------|
| GUI モード | 引数なし起動 | 設定・接続確認・手動生成・履歴確認 |
| `run-once` | Task Scheduler から呼び出す | スケジュール枠の未処理確認 → 生成 → 終了 |
| `generate` | 手動 CLI 実行 | 即時生成 → 終了 |
| `check-*` | 手動 CLI 実行 | Calendar / News / AI の接続確認 |

**「設定は GUI」「定期処理は CLI」** の役割分担で常駐を避ける。

---

## 技術スタック

* UI: **WPF + WPF-UI**（`<ui:FluentWindow>` ベース、Mica バックドロップ）
* ホスト / DI: **Kamishibai**（WPF + Generic Host 統合）
* CLI: **ConsoleAppFramework**
* フレームワーク: **.NET 10**（`net10.0-windows10.0.22621.0`）

---

## サービス構成

サービスはすべて **Singleton**。**interface を設けず具体クラス直接参照**。

| サービス | 責務 |
|---------|------|
| `AppConfigService` | JSON 設定の読み書き（`%LocalAppData%/StudioFreesia/WondayWall/config.json`） |
| `ContextService` | Google Calendar + RSS フィードから `ContextBuildResult` を構築 |
| `GoogleAiService` | Gemini で壁紙画像を生成・保存（2 ステップ生成） |
| `WallpaperService` | 仮想デスクトップ API / Win32 で壁紙を適用 |
| `GenerationCoordinator` | 上記サービスを順次呼び出すオーケストレーター |
| `HistoryService` | 生成履歴を `history.json` に保存（最大 100 件） |
| `TaskSchedulerService` | Windows Task Scheduler へのタスク登録・削除 |
| `UpdateChecker` | GitHub Releases API で新バージョン確認（BackgroundService） |

---

## 生成フロー

`GenerationCoordinator` が GUI・CLI 両方から呼ばれる。処理本体はここに集約する。

```
GenerationCoordinator（SemaphoreSlim で多重実行防止）
  ├─ ContextService.BuildContextAsync()
  │   ├─ Google Calendar API → カレンダーイベント
  │   └─ RSS フィード + OGP 解析 → ニューストピック
  ├─ GoogleAiService.GenerateWallpaperAsync()（2 ステップ生成）
  │   ├─ Step 1: Gemini Flash でテキストプロンプト詳細化（Google Search グラウンディング）
  │   └─ Step 2: Gemini Flash Image で画像生成
  │       └─ Flex ティア失敗時は Standard にフォールバック
  ├─ WallpaperService.SetWallpaperAsync()
  └─ HistoryService.Append()
```

`run-once` 専用の `RunScheduledAsync()` はスキップ判定（`SkipGenerationWhenNoChanges`）を行ってから上記を呼ぶ。

---

## MVVM 方針

* CommunityToolkit.MVVM の `[ObservableProperty]`・`[RelayCommand]` を使う
* ViewModel は **`MainWindowViewModel` 1 個**。分割しない
* MainWindow は薄く保つ（API 呼び出し・壁紙変更・スケジューリングを置かない）

---

## 定期実行

定期実行は **Windows Task Scheduler** に委ねる。GUI の「スケジューラ有効化」ボタンから `TaskSchedulerService` 経由でタスクを登録・削除する。

* 1 日あたりの実行回数（1 / 2 / 3 / 4 / 6 / 8 / 12 / 24 回）を UI で設定
* スロット時刻の計算は `ScheduleHelper` が担う
* 常駐タイマーやトレイからの定期実行管理は行わない

---

## セキュリティ

* **Google AI API キー**: `PasswordVault`（Windows Credential Manager）で暗号化保管
* **OAuth トークン**: `%LocalAppData%/StudioFreesia/WondayWall/calendar-token/` にキャッシュ

---

## 将来の拡張ポイント

* タスクトレイ常駐
* 複数モニタ個別壁紙
* `PromptBuilder` の分離
* `ContextService` の分割（`CalendarService` / `NewsService`）
* interface 導入