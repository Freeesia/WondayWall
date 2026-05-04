# WPF 壁紙生成アプリ 実装指針

## 概要

本書は、WPF ベースの壁紙生成アプリの実装指針をまとめたものである。
設計の美しさよりも **完成の速さ、修正のしやすさ、構成の分かりやすさ** を優先する。

本アプリは、ユーザーの予定や関心に応じて画像を生成し、壁紙として適用する。常駐アプリにはせず、**GUI モード** と **CLI モード** を 1 つの exe にまとめたハイブリッド構成を採用する。

---

## 前提条件

* UI: WPF
* UI ライブラリ: **WPF-UI 4.2.0**
* ホスト / DI: **Kamishibai 3.1.0**
* コマンドライン: **ConsoleAppFramework 5.x**
* フレームワーク: **.NET 10**（`net10.0-windows10.0.22621.0`）
* プロジェクト数: **1**
* 本書は **実装指針のみ** を扱う

---

## 採用方針

**常駐しないハイブリッド型** とする。

ここでいうハイブリッド型とは、トレイ常駐型アプリではなく、**1 つの exe を GUI と CLI の両方で使い分ける構成** を指す。

### 動作イメージ

* ユーザーが通常起動した場合
  → **WPF の設定 UI を開く**
* Task Scheduler などから定期実行された場合
  → `run-once` で **UI を表示せずに 1 回だけ処理を行って終了する**
* 手動実行用コマンドを使う場合
  → `generate` で **同様の処理を即時実行する**

つまり、**通常時は常駐しない**。
同じ exe から GUI と CLI の両方を提供するため、この構成をハイブリッド型とする。

---

## この構成を採用する理由

本アプリで必要となる基本処理は次の 4 つである。

1. カレンダーやニュースを取得する
2. Google AI で画像を生成する
3. 画像を壁紙として適用する
4. 処理を終了する

この処理において、初期段階では常駐は必須ではない。むしろ常駐型にすると、次のような複雑さが追加される。

* タスクトレイの実装
* 多重起動制御
* 起動中状態の同期
* 常駐中の再認証導線
* メモリ常駐の管理
* UI とバックグラウンド処理の寿命管理

初期版ではこれらを避け、**「設定は GUI」「定期処理は CLI」** という役割分担にすることで、構成を単純に保つ。

---

## 実行モード

## GUI モード

通常起動時のモードであり、主に設定と確認に使用する。

### 用途

* 設定編集
* 接続確認
* 予定 / ニュースのプレビュー
* 手動生成
* 履歴確認

### 起動例

```powershell
WondayWall.exe
```

## RunOnce モード

定期実行用のモードであり、処理を 1 回だけ実行して終了する。

### 用途

* データ取得
* 画像生成
* 壁紙適用
* ログ保存
* 終了

### 起動例

```powershell
WondayWall.exe run-once
```

または

```powershell
WondayWall.exe generate
```

---

## 技術構成

## UI

* **WPF**
* **WPF-UI**

### 役割

* MainWindow の見た目
* タブ UI
* ダイアログ
* 画像プレビュー
* 設定編集

## Host / DI

* **Kamishibai**

### 役割

* WPF と Generic Host の統合
* Service 登録
* View / ViewModel の解決
* 起動フローの整理

## CLI

* **ConsoleAppFramework**

### 役割

* `run-once`
* `generate`
* `check-calendar`
* `check-news`
* `check-google-ai`

のようなコマンドを 1 つの exe に載せる。

---

## 全体構成

### 起動フロー

1. `Program.cs` で起動する
2. `ConsoleAppFramework` で引数を判定する
3. GUI モードなら Kamishibai 経由で WPF を起動する
4. CLI モードなら Host から必要なサービスを解決する
5. 処理完了後に終了する

---

## 初期版の最小フォルダ構成

```text
WondayWall/
  App.xaml
  App.xaml.cs
  Program.cs

  Views/
    MainWindow.xaml
    MainWindow.xaml.cs

  ViewModels/
    MainWindowViewModel.cs

  Models/
    AppConfig.cs
    AvailableCalendar.cs
    CalendarEventItem.cs
    ContextBuildResult.cs
    GeneratedImageInfo.cs
    GoogleAiServiceTier.cs
    HistoryItem.cs
    NewsTopicItem.cs
    PromptContext.cs
    PromptTemplate.cs
    UpdateInfo.cs

  Services/
    AppConfigService.cs
    ContextService.cs
    GenerationCoordinator.cs
    GoogleAiService.cs
    HistoryService.cs
    TaskSchedulerService.cs
    UpdateChecker.cs
    WallpaperService.cs

  Commands/
    CliCommands.cs

  ComponentModel/
    CredentialSecretAttribute.cs
    CredentialSecretJsonConverter.cs
    GenerativeModelEx.cs

  Utils/
    AppLinks.cs
    CredentialSecretStore.cs
    DisplayHelper.cs
    FileNameHelper.cs
    JsonFileHelper.cs
    PathUtility.cs
    ScheduleHelper.cs
    UrlToFaviconConverter.cs
```

---

## クラス設計方針

**interface をほぼ作らず、具体クラス中心で実装する**。

差し替え先が存在しない段階で抽象化を増やすと、構成が見えにくくなり、保守コストが上がりやすい。まずは責務のまとまりごとにクラスを切り、必要になった時点で分割や抽象化を行う。

### AppConfigService

#### 役割

* 設定の読み込み
* 設定の保存
* 保存先ディレクトリの決定
* デフォルト設定の生成

#### 責務

* JSON 入出力
* 設定ファイルパスの管理

### ContextService

#### 役割

* Google Calendar から予定を取得する
* RSS / ニュースを取得する
* `ContextBuildResult`（`PromptContext` + カレンダーイベント + ニューストピック）を返す

#### 責務

* Google OAuth / Calendar API 呼び出し
* RSS 取得と OGP メタデータ解析
* 興味キーワードによる抽出
* 予定 / ニュースの要約材料作成

`CalendarService` と `NewsService` には分割しない。

### GoogleAiService

#### 役割

* `PromptContext` からプロンプトを組み立てる
* Google AI に画像生成を依頼する
* 結果画像を保存する

#### 責務

* **2 ステップ生成**: まず Gemini Flash でテキストプロンプトを詳細化（Google Search グラウンディング有効）し、次に Gemini Flash Image で画像生成
* Flex / Standard サービスティア切り替え（Flex 失敗時は Standard にフォールバック）
* エラー処理・Polly リトライ

`PromptBuilder` は分離しない。

### WallpaperService

#### 役割

* 壁紙を反映する
* 画像パスを検証する
* 最終適用画像を管理する

#### 責務

* `IDesktopWallpaper` / 仮想デスクトップ API による壁紙変更
* ロック画面更新オプション（`UpdateLockScreen`）

### GenerationCoordinator

#### 役割

* 全体フローの司令塔
* GUI の手動生成と CLI の `run-once` を共通化する

#### 責務

* コンテキスト取得
* 画像生成
* 壁紙適用
* 履歴追加
* 同時実行防止（`SemaphoreSlim(1,1)`）
* スキップ判定（`SkipGenerationWhenNoChanges` で変化なければスキップ）

重要なのは、**GUI からも CLI からもこのクラスを呼ぶこと** である。処理本体を MainWindow 側に持たせない。

エントリポイントは 2 つ。
* `RunAsync()` — 手動生成（`generate` コマンド・GUI ボタン共用）
* `RunScheduledAsync()` — スケジュール判定付き（`run-once` コマンド用）

### HistoryService

#### 役割

* 生成履歴を保存・管理する

#### 責務

* `history.json` への追記（最大 100 件）
* Singleton で保持し全体から参照

### TaskSchedulerService

#### 役割

* Windows Task Scheduler に WondayWall タスクを登録・削除する

#### 責務

* `run-once` を指定スケジュールで実行するタスクの作成
* タスクの有効化・無効化

### UpdateChecker

#### 役割

* GitHub Releases API で新バージョンを確認する

#### 責務

* `BackgroundService` として GUI 起動時にバックグラウンドで実行
* 新バージョンがあればトースト通知

### CliCommands

#### 役割

* `ConsoleAppFramework` のコマンド定義

#### コマンド一覧

| コマンド | 説明 |
|---------|------|
| `run-once` | スケジュール枠が未処理なら実行（Task Scheduler 用） |
| `generate` | 即時生成（手動実行用） |
| `check-calendar` | Google Calendar 接続テスト・イベント一覧表示 |
| `check-news` | RSS フィード取得・トピック表示 |
| `check-google-ai` | Google AI API 接続テスト（サンプル画像生成） |

CLI 側では、できるだけ `GenerationCoordinator` や `ContextService` を呼び出すだけにし、CLI 専用ロジックを増やさない。

---

## ViewModel 方針

**MainWindowViewModel 1 個中心** で構成する。

### MainWindowViewModel が持つもの

* 設定 (`AppConfig`)
* カレンダー接続状態（`CalendarStatus`, `IsCalendarConnected`）
* 直近予定一覧（`RecentEvents`）
* 直近ニュース一覧（`RecentNews`）
* 生成中フラグ（`IsGenerating`）
* 最後に生成した画像情報（`LastGeneratedImage`, `LastImagePreviewPath`）
* 前回実行結果メッセージ（`LastResultMessage`）
* 生成履歴（`History`）
* RSS ソース一覧（`RssSources`）
* 利用可能なカレンダー一覧（`AvailableCalendars`）
* プロンプトテンプレート（`SelectedPromptTemplate`）
* Task Scheduler 有効フラグ（`IsTaskSchedulerEnabled`）
* 更新情報（`HasUpdate`, `LatestVersion`, `IsCheckingUpdate`）
* セットアップウィザード表示（`ShowSetupWizard`）
* 手動生成コマンド（`GenerateCommand`）
* カレンダー確認コマンド（`CheckCalendarCommand`）
* ニュース確認コマンド（`CheckNewsCommand`）
* スケジューラ有効化 / 無効化コマンド
* RSS ソース追加 / 削除コマンド
* 更新インストール・リリースノート表示・更新チェックコマンド

次の分割は行わない。

* `SettingsViewModel`
* `CalendarViewModel`
* `NewsViewModel`
* `HistoryViewModel`

---

## 画面構成

**1 ウィンドウ + 複数タブ** 構成。ベースは `<ui:FluentWindow>`（Mica バックドロップ）。

### タイトルバー

* 更新チェックボタン
* 新バージョン通知バナー

### セットアップウィザード（初回のみ）

* API キー入力
* Google Calendar 接続

### タブ：設定

* Google AI API キー設定
* 1 日あたりの実行回数（Task Scheduler 連動）
* Task Scheduler 有効化 / 無効化ボタン

### タブ：カレンダー連携

* Google Calendar 接続状態
* 取得対象カレンダー選択（`AvailableCalendars` チェックリスト）
* 直近イベントプレビュー
* 接続確認ボタン

### タブ：RSS 設定

* RSS ソース追加 / 削除
* 取得トピックプレビュー
* ニュース確認ボタン

### タブ：プロンプトテンプレート

* テンプレート選択
* プロンプト内容表示・編集

### タブ：履歴

* 生成履歴一覧（ダブルクリックで画像表示）

### 固定フッター / ホームエリア

* 最後に生成した壁紙プレビュー
* 手動生成ボタン（`IsGenerating` で制御）
* 前回実行結果メッセージ

---

## Program.cs の方針

`Program.cs` で実行モードを分岐する。

### 役割

* Host / DI 初期化
* `ConsoleAppFramework` 起動
* GUI モード時のみ WPF（Kamishibai）を起動
* CLI モード時は処理を実行して終了

### 共通で登録するもの（Singleton）

* `AppConfigService`
* `ContextService`
* `GoogleAiService`
* `WallpaperService`
* `HistoryService`
* `GenerationCoordinator`
* `TaskSchedulerService`
* HttpClient（`"WondayWall"` 30 秒、`"Gemini"` 30 分 + Polly リトライ）

### GUI 専用で登録するもの

* `UpdateChecker`（`IHostedService` として登録）
* `IGitHubClient`（Octokit）
* HttpClient（`"WondayWallUpdate"` 10 分）
* `MainWindow` / `MainWindowViewModel`（`AddPresentation<MainWindow, MainWindowViewModel>`）

### 登録しなくてよいもの

* 細かい interface
* 過剰な PresentationService
* 分割しすぎた Options クラス

---

## App.xaml の方針

役割は最小限にとどめる。

* WPF-UI のテーマ辞書
* 共通スタイル
* 必要であれば例外フック

主要な起動ロジックは `Program.cs` に寄せる。

---

## MainWindow の方針

MainWindow は薄く保つ。

### 役割

* レイアウト
* バインディング
* ダイアログの起点

### 置かないもの

* API 呼び出し本体
* 壁紙変更本体
* スケジューリング本体

---

## モデル

### AppConfig

* Google AI API キー（`[CredentialSecret]` 属性 → `PasswordVault` で暗号化保管）
* Google Calendar カレンダー ID 一覧
* RSS ソース一覧
* ユーザー追加プロンプト
* 1 日あたりの実行回数（`RunsPerDay`）
* ベース壁紙を使うかどうか（`UseCurrentWallpaperAsBase`）
* 変化なしのときスキップ（`SkipGenerationWhenNoChanges`）
* ロック画面も更新（`UpdateLockScreen`）

### CalendarEventItem

* タイトル
* 開始 / 終了時刻
* 場所
* 概要

（UI 表示用。プロンプト向けには `PromptCalendarEvent` を使う）

### NewsTopicItem

* タイトル
* 要約
* URL
* 公開日時
* OGP 画像 URL

（UI 表示用。プロンプト向けには `PromptNewsTopic` を使う）

### PromptContext

* カレンダーイベント（`PromptCalendarEvent` のリスト）
* ニューストピック（`PromptNewsTopic` のリスト）
* 画像サイズ・アスペクト比
* ベース画像パス
* 追加制約

### ContextBuildResult

* `PromptContext`
* `CalendarEventItem` リスト（UI 表示用）
* `NewsTopicItem` リスト（UI 表示用）

`ContextService.BuildContextAsync()` の戻り値。

### GeneratedImageInfo

* ファイルパス
* 生成日時
* 使用プロンプト
* サービスティア（`GoogleAiServiceTier`）
* 元コンテキスト

### HistoryItem

* 実行日時
* 成功 / 失敗
* エラー概要
* 適用画像パス
* 使用したカレンダーイベント
* 使用したニューストピック
* サービスティア
* スキップ済みフラグ（`IsSkipped`）

### AvailableCalendar

* カレンダー ID
* 表示名
* プライマリカレンダーかどうか
* 選択状態（UI チェックボックス用）

### GoogleAiServiceTier

* `Standard`
* `Flex`（失敗時 Standard にフォールバック）

### PromptTemplate

* テンプレート名
* テンプレート本文

### UpdateInfo

* バージョン
* リリース URL
* ダウンロードパス
* 確認日時
* スキップフラグ

---

## 実行フロー

### GUI から手動生成する場合

1. `MainWindowViewModel` から `GenerationCoordinator.RunAsync()` を呼ぶ
2. `ContextService.BuildContextAsync()` で予定 / ニュースを取得し `ContextBuildResult` を返す
3. `GoogleAiService.GenerateWallpaperAsync()` で画像生成（テキストプロンプト詳細化 → 画像生成の 2 ステップ）
4. `WallpaperService` で壁紙を適用する
5. `HistoryService` に結果を追記する
6. ViewModel の ObservableCollection を更新して画面を更新する

### CLI の `run-once` を実行する場合

1. `CliCommands` から `GenerationCoordinator.RunScheduledAsync()` を呼ぶ
2. スケジュール枠が未処理かを確認し、スキップ条件を評価する
3. （生成対象の場合）上記 2〜5 と同様の処理を実行する
4. 終了コードを返して終了する

**処理本体は共通化する。**

---

## 定期実行の考え方

定期実行は **Windows Task Scheduler** を使う前提とする。GUI 上の「スケジューラ有効化」ボタンから `TaskSchedulerService` 経由でタスクの登録・削除が可能。

### 方式の例

* ログオン時実行
* 1 日 1〜24 回（`SupportedRunsPerDay` = [1, 2, 3, 4, 6, 8, 12, 24]）

スロット時刻の計算は `ScheduleHelper` が担う。

### アプリ側でやること

* `run-once` コマンドを用意する（`0` を成功、`1` を失敗として返す）
* `TaskSchedulerService` でタスクを登録・削除する
* `run-once` 呼び出し時に `SkipGenerationWhenNoChanges` でスキップ判定する

### アプリ側でやらないこと

* 常駐タイマー
* トレイからの定期実行管理

---

## ライブラリ

### 採用しているもの

| パッケージ | バージョン | 用途 |
|-----------|----------|------|
| `CommunityToolkit.Mvvm` | 8.4.2 | MVVM / `[ObservableProperty]` / `[RelayCommand]` |
| `WPF-UI` | 4.2.0 | Fluent WPF コンポーネント |
| `Kamishibai` / `Kamishibai.Hosting` | 3.1.0 | WPF + Generic Host 統合・DI |
| `ConsoleAppFramework` | 5.x | CLI コマンドルーティング |
| `Google_GenerativeAI` | 3.6.4 | Gemini API（テキスト＋画像生成） |
| `Google.Apis.Calendar.v3` | 1.73.x | Google Calendar API |
| `Microsoft.Extensions.Hosting` | 10.x | ホスティング・BackgroundService |
| `Microsoft.Extensions.Http` | 10.x | `IHttpClientFactory` |
| `Microsoft.Extensions.Http.Resilience` | 10.x | Polly リトライ |
| `System.ServiceModel.Syndication` | 10.x | RSS フィード解析 |
| `OpenGraph-Net` | 4.0.1 | OGP メタデータ解析 |
| `Octokit` | 14.x | GitHub Releases API（更新チェック用） |
| `Microsoft.Toolkit.Uwp.Notifications` | 7.1.3 | トースト通知 |
| `Slions.VirtualDesktop.WPF` | 6.9.2 | 仮想デスクトップ別壁紙 |
| `TaskScheduler` | 2.x | Windows Task Scheduler 操作 |
| `Microsoft.Windows.CsWin32` | 0.3.x | Win32 API ラッパー生成 |
| `Nito.AsyncEx.Coordination` | 5.1.2 | `AsyncLock` |

### 採用していないもの

* MediatR
* ReactiveUI
* AutoMapper
* Repository パターン一式
* 大規模ログ基盤
* interface の大量定義

---

## 実装ステップ（完了済み）

### Step 1 ✅

* WPF-UI で MainWindow を作る
* Kamishibai で起動する
* 設定保存 / 読み込みを作る

### Step 2 ✅

* `WallpaperService` を作る
* 手動で画像を選んで壁紙適用できるようにする

### Step 3 ✅

* `ConsoleAppFramework` を導入する
* `run-once` コマンドを先に作る
* GUI と CLI の共存を成立させる

### Step 4 ✅

* Google AI 接続
* 固定プロンプトで画像生成
* 保存まで実装

### Step 5 ✅

* Google Calendar 接続
* 予定取得
* 画面表示

### Step 6 ✅

* RSS 取得
* OGP メタデータ解析
* 画面表示

### Step 7 ✅

* `GenerationCoordinator` で全体を接続する
* `run-once` を完成させる
* Task Scheduler 連動（`TaskSchedulerService`）

### Step 8 ✅

* Gemini 2 ステップ生成（テキストプロンプト詳細化 → 画像生成）
* Flex / Standard サービスティア対応
* 仮想デスクトップ別壁紙対応
* `UpdateChecker`（GitHub Releases 自動チェック・トースト通知）

---

## 将来の拡張ポイント

必要になった段階で追加する。

* タスクトレイ常駐
* 複数モニタ個別壁紙
* `PromptBuilder` の分離
* `ContextService` の分割（`CalendarService` / `NewsService`）
* interface 導入

---

## 方針まとめ

* **常駐しない**
* **同じ exe で GUI と CLI を両立する**
* **WPF-UI + Kamishibai + ConsoleAppFramework を採用する**
* **ViewModel は `MainWindowViewModel` 1 個**
* **サービスは具体クラス直接参照（interface なし）**
* **Task Scheduler 連動で定期実行する（`TaskSchedulerService` でアプリ内登録）**
* **API キーは `PasswordVault` で暗号化保管**
* **Gemini は 2 ステップ生成（テキストプロンプト詳細化 → 画像生成）**
