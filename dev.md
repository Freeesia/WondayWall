# WPF 壁紙生成アプリ 実装指針

## 概要

本書は、WPF ベースの壁紙生成アプリを **最小限の構成で実装するための指針** をまとめたものである。
対象は初期実装であり、設計の美しさよりも **完成の速さ、修正のしやすさ、構成の分かりやすさ** を優先する。

本アプリは、ユーザーの予定や関心に応じて画像を生成し、壁紙として適用する。初期版では常駐アプリにはせず、**GUI モード** と **CLI モード** を 1 つの exe にまとめたハイブリッド構成を採用する。

---

## 前提条件

* UI: WPF
* UI ライブラリ: **WPF-UI**
* ホスト / DI: **Kamishibai**
* コマンドライン: **ConsoleAppFramework**
* フレームワーク: **.NET 10**
* プロジェクト数: **1**
* 実装は別環境で行う
* 本書は **実装指針のみ** を扱う
* 初期仕様では **仮想デスクトップ対応を含めない**

---

## 採用方針

初期版は **常駐しないハイブリッド型** とする。

ここでいうハイブリッド型とは、トレイ常駐型アプリではなく、**1 つの exe を GUI と CLI の両方で使い分ける構成** を指す。

### 動作イメージ

* ユーザーが通常起動した場合
  → **WPF の設定 UI を開く**
* Task Scheduler などから定期実行された場合
  → `run-once` で **UI を表示せずに 1 回だけ処理を行って終了する**
* 手動実行用コマンドを使う場合
  → `generate` で **同様の処理を即時実行する**

つまり、**通常時は常駐しない**。
一方で、同じ exe から GUI と CLI の両方を提供するため、この構成をハイブリッド型とする。

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
AppName.exe
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
AppName.exe run-once
```

または

```powershell
AppName.exe generate
```

コマンド名は `ConsoleAppFramework` に合わせて最終調整する。

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
AppName/
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
    CalendarEventItem.cs
    NewsTopicItem.cs
    PromptContext.cs
    GeneratedImageInfo.cs
    HistoryItem.cs

  Services/
    AppConfigService.cs
    ContextService.cs
    GoogleAiService.cs
    WallpaperService.cs
    GenerationCoordinator.cs

  Commands/
    CliCommands.cs

  Utils/
    JsonFileHelper.cs
    FileNameHelper.cs
    TimeHelper.cs
```

---

## クラス設計方針

初期版では **interface をほぼ作らず、具体クラス中心で実装する**。

差し替え先が存在しない段階で抽象化を増やすと、構成が見えにくくなり、保守コストが上がりやすい。まずは責務のまとまりごとにクラスを切り、必要になった時点で分割や抽象化を行う。

### レビュー観点（追記）

* **メソッド分割は責務単位で行う。**
  1～2 行の単純ラッパーや、値をそのまま受け渡すだけのメソッドは原則増やさない。
* **重複チェックを優先して排除する。**
  例: 同じトークン読込・同じバリデーションを別メソッドで繰り返していないかを確認する。
* **可読性と追跡容易性を優先する。**
  分割によって呼び出しチェーンが長くなりすぎる場合は、適度に統合して意図が 1 画面で読めるようにする。

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
* `PromptContext` 用に整形する

#### 責務

* Google OAuth / Calendar API 呼び出し
* RSS 取得
* 興味キーワードによる抽出
* 予定 / ニュースの要約材料作成

初期版では `CalendarService` と `NewsService` に分割しない。

### GoogleAiService

#### 役割

* `PromptContext` からプロンプトを組み立てる
* Google AI に画像生成を依頼する
* 結果画像を保存する

#### 責務

* プロンプト生成
* Google GenAI 呼び出し
* エラー処理
* 必要に応じた簡易リトライ

初期版では `PromptBuilder` を分離しない。

### WallpaperService

#### 役割

* 壁紙を反映する
* 画像パスを検証する
* 最終適用画像を管理する

#### 責務

* Win32 による壁紙変更
* 適用画像の保持

### GenerationCoordinator

#### 役割

* 全体フローの司令塔
* GUI の手動生成と CLI の `run-once` を共通化する

#### 責務

* コンテキスト取得
* 画像生成
* 壁紙適用
* 履歴追加
* 同時実行防止

重要なのは、**GUI からも CLI からもこのクラスを呼ぶこと** である。処理本体を MainWindow 側に持たせない。

### CliCommands

#### 役割

* `ConsoleAppFramework` のコマンド定義

#### 候補コマンド

* `run-once`
* `generate`
* `check-calendar`
* `check-news`
* `check-google-ai`

CLI 側では、できるだけ `GenerationCoordinator` や `ContextService` を呼び出すだけにし、CLI 専用ロジックを増やさない。

---

## ViewModel 方針

初期版は **MainWindowViewModel 1 個中心** で構成する。

### MainWindowViewModel が持つもの

* 設定 (`AppConfig`)
* 接続状態
* 直近予定一覧
* 直近ニュース一覧
* 生成プレビュー情報
* 最終生成画像
* 履歴
* 手動生成コマンド
* 保存コマンド
* 接続確認コマンド

初期版では次の分割は行わない。

* `SettingsViewModel`
* `CalendarViewModel`
* `NewsViewModel`
* `HistoryViewModel`

---

## 画面構成

初期版は **1 ウィンドウ + 3 タブ** で十分とする。

### ホーム

* 現在の壁紙プレビュー
* 手動生成ボタン
* 次回定期実行の説明
* 直近実行結果

### データ

* Google Calendar 接続状態
* 取得対象カレンダー
* 興味キーワード
* RSS 一覧
* 取得結果プレビュー

### 設定

* Google AI API 設定
* 更新間隔
* 保存先
* Task Scheduler 用の説明
* ログ出力設定

---

## Program.cs の方針

`Program.cs` で実行モードを分岐する。

### 役割

* 多重起動制御（必要であれば GUI のみ）
* Host / DI 初期化
* `ConsoleAppFramework` 起動
* GUI モード時のみ WPF を起動
* CLI モード時は処理を実行して終了

### 登録するもの

* `AppConfigService`
* `ContextService`
* `GoogleAiService`
* `WallpaperService`
* `GenerationCoordinator`
* `CliCommands`
* `MainWindow`
* `MainWindowViewModel`

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

* Google AI API Key または設定
* Google Calendar 設定
* 興味キーワード
* RSS ソース一覧
* 更新間隔
* 保存先
* ログ設定

### CalendarEventItem

* タイトル
* 開始 / 終了時刻
* 場所
* 概要

### NewsTopicItem

* タイトル
* 要約
* URL
* 取得日時
* 一致キーワード

### PromptContext

* 予定要約
* ニュース要約
* 雰囲気キーワード
* 画像サイズ
* 追加制約

### GeneratedImageInfo

* ファイルパス
* 生成日時
* 使用プロンプト
* 元コンテキスト

### HistoryItem

* 実行日時
* 成功 / 失敗
* エラー概要
* 適用画像パス

---

## 実行フロー

### GUI から手動生成する場合

1. `MainWindowViewModel` から `GenerationCoordinator` を呼ぶ
2. `ContextService` で予定 / ニュースを取得する
3. `GoogleAiService` で画像を生成する
4. `WallpaperService` で適用する
5. 履歴を更新する
6. 画面を更新する

### CLI の `run-once` を実行する場合

1. `CliCommands` から `GenerationCoordinator` を呼ぶ
2. `ContextService` で予定 / ニュースを取得する
3. `GoogleAiService` で画像を生成する
4. `WallpaperService` で適用する
5. 履歴を更新する
6. 終了コードを返して終了する

**処理本体は共通化する。**

---

## 定期実行の考え方

定期実行はアプリ内常駐ではなく、**Windows Task Scheduler** を使う前提とする。

### 方式の例

* ログオン時実行
* 1 時間ごとの実行
* 朝 / 昼 / 夜だけ実行

これらはタスクスケジューラ側で設定する。

### アプリ側でやること

* `run-once` コマンドを用意する
* `0` を成功、`1` を失敗などの終了コードとして返す
* ログを残す

### アプリ側でやらないこと

* 常駐タイマー
* トレイからの定期実行管理

初期版ではここまでで十分である。

---

## ライブラリ方針

### 採用するもの

* `CommunityToolkit.Mvvm`
* `WPF-UI`
* `Kamishibai.Hosting`
* `ConsoleAppFramework`
* `Google.GenAI`
* `Google.Apis.Calendar.v3`
* `Microsoft.Extensions.Hosting`
* `Microsoft.Extensions.DependencyInjection`
* `System.ServiceModel.Syndication`
* 必要に応じて `SixLabors.ImageSharp`

### 初期版では入れないもの

* MediatR
* ReactiveUI
* AutoMapper
* Polly
* Repository パターン一式
* 大規模ログ基盤
* interface の大量定義

---

## 実装順序

### Step 1

* WPF-UI で MainWindow を作る
* Kamishibai で起動する
* 設定保存 / 読み込みを作る

### Step 2

* `WallpaperService` を作る
* 手動で画像を選んで壁紙適用できるようにする

### Step 3

* `ConsoleAppFramework` を導入する
* `run-once` コマンドを先に作る
* GUI と CLI の共存を成立させる

### Step 4

* Google AI 接続
* 固定プロンプトで画像生成
* 保存まで実装

### Step 5

* Google Calendar 接続
* 予定取得
* 画面表示

### Step 6

* RSS 取得
* 興味キーワード抽出
* 画面表示

### Step 7

* `GenerationCoordinator` で全体を接続する
* `run-once` を完成させる
* Task Scheduler 前提の運用にする

---

## 将来の拡張ポイント

必要になった段階で追加する。

* タスクトレイ常駐
* 仮想デスクトップ別の壁紙
* 複数モニタ対応
* `PromptBuilder` の分離
* `ContextService` の分割
* interface 導入

初期版では行わない。

---

## 最終方針

初期版は次の方針で十分である。

* **常駐しない**
* **同じ exe で GUI と CLI を両立する**
* **WPF-UI + Kamishibai + ConsoleAppFramework を採用する**
* **ViewModel は 1 個中心で構成する**
* **サービスは 5 個程度に抑える**
* **interface は基本的に作らない**
* **Task Scheduler 前提で定期実行する**

この構成であれば、設計過多を避けつつ、後から拡張しやすい。
