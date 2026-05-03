# WondayWall Android版 開発仕様

## 目的

WondayWall Android版は、ユーザーの予定・ニュース・ユーザープロンプトをもとに、Android端末向けの壁紙画像を生成し、ホーム画面またはロック画面へ適用するアプリである。

Windows版の「予定や興味をもとに壁紙を生成して適用する」という基本体験と、iOS版のモバイル向けバックグラウンド生成・通知・共有の考え方を踏襲する。

Androidでは通常アプリから壁紙を変更できるため、iOS版とは異なり、生成画像の保存・共有だけでなく、`WallpaperManager` による壁紙の直接適用を主要機能とする。

## 基本方針

- 手動生成とバックグラウンド定期生成を提供する。
- 主要なクラス名はWindows版に揃える。
- 生成処理は `GenerationCoordinator` に集約する。
- 壁紙関連の処理は `WallpaperService` に集約する。
- 定期実行関連の処理は、Android版でも `TaskSchedulerService` に集約する。
- `TaskSchedulerService` の内部実装として `WorkManager` を使う。
- スケジュール設定は `RunsPerDay`、つまり「1日あたりの自動生成回数」で管理する。
- 厳密な時刻実行は保証しない。
- アプリ起動時・フォアグラウンド復帰時にも未処理スロットを確認し、取りこぼしを補完する。
- 常駐サービス型にはしない。
- 自前の中間サーバーは用意しない。
- Google AI画像生成のjobId復旧は行わない。
- 通信断、アプリ停止、OS中断、生成失敗時は失敗履歴を残し、次回以降に再生成できるようにする。

## Windows版と揃えるクラス名

Android版では、OS固有の実装詳細が異なっても、主要なアプリケーション層のクラス名はWindows版に揃える。

| 種別 | Android版で使うクラス名 | 備考 |
|---|---|---|
| 設定 | `AppConfigService` | DataStoreまたはJSONへの保存を担当する |
| 文脈作成 | `ContextService` | Google Calendar、RSS、ユーザープロンプトから生成文脈を作る |
| 画像生成 | `GoogleAiService` | Google AI呼び出しと生成画像保存を担当する |
| 壁紙処理 | `WallpaperService` | 画像調整、壁紙適用、写真保存、共有を担当する |
| 生成統括 | `GenerationCoordinator` | UIとWorkerの両方から呼ばれる中心クラス |
| 履歴 | `HistoryService` | 成功、失敗、スキップ履歴を保存する |
| 定期実行 | `TaskSchedulerService` | Androidでは内部でWorkManagerを使う |

Android固有の入口クラスは、Windows版に対応する名前がないためAndroid名を使う。

| 種別 | Android固有クラス名 | 備考 |
|---|---|---|
| Worker | `BackgroundGenerationWorker` | WorkManagerから起動され、`GenerationCoordinator` を呼ぶだけにする |
| 通知 | `NotificationService` | 生成完了、生成失敗、生成中通知を扱う |

`ImagePrepareService` や `BackgroundWorkScheduler` のようなAndroid版独自の主要サービス名は作らない。
画像調整は `WallpaperService`、定期実行管理は `TaskSchedulerService` の責務に含める。

## 提供機能

- Google AIによるAndroid向け壁紙画像の生成
- Google Calendarの予定を使った生成コンテキスト作成
- RSS/ニュースを使った生成コンテキスト作成
- ユーザープロンプトを使った生成コンテキスト作成
- 手動生成
- バックグラウンド定期生成
- アプリ内画像保存
- 生成履歴保存
- ホーム画面壁紙への適用
- ロック画面壁紙への適用
- ホーム画面とロック画面の両方への適用
- 写真/ギャラリー保存
- 共有シート表示
- 生成完了通知
- 生成失敗通知
- 初回セットアップウィザード

## 対象外

- ライブ壁紙
- 常駐サービス化
- 厳密な時刻実行保証
- jobIdによる生成結果の後追い取得
- 自前中間サーバー
- 複数端末同期
- 複数ランチャー固有仕様への完全対応
- メーカー独自ロック画面への完全対応

## 技術構成

初期実装ではネイティブAndroidアプリとして実装する。

- 言語: Kotlin
- UI: Jetpack Compose
- 状態管理: ViewModel + StateFlow
- 非同期処理: Kotlin Coroutines
- 定期実行: WorkManager
- 設定保存: DataStore
- 履歴保存: JSONファイル、必要になった段階でRoomを検討
- 壁紙適用: WallpaperManager
- 画像読み込み/表示: Coil
- 画像加工: Bitmap / ImageDecoder
- 通知: NotificationManager
- 共有: Android Sharesheet + FileProvider
- DI: 初期版ではシンプルな手動DI、必要になればHiltを検討

初期版では過剰な抽象化を避ける。
Windows版と同様に、まずは責務単位で具体クラスを切り、差し替えが必要になった段階でinterface化する。

## 画像仕様

Android版では縦長スマートフォン壁紙を基本とする。

### 基本方針

- 縦長画像を生成する。
- 9:16 から 20:9 程度の画面比率を想定する。
- テキストや細かい文字を入れない。
- 重要な被写体は中央寄せにする。
- 上部の時計、通知、カメラ領域で隠れても破綻しない構図にする。
- 下部のナビゲーションバーやジェスチャー領域で隠れても破綻しない構図にする。
- ホーム画面アイコンの視認性を妨げにくい構図にする。
- ランチャーのスクロール壁紙対応は初期版では必須にしない。

### 保存方針

生成画像はアプリ内に保存する。
必要に応じて、`WallpaperService` が適用用にリサイズまたはクロップした画像も保存する。

```text
wallpapers/original/
  Google AIから受け取った原本

wallpapers/applied/
  端末向けに調整した適用画像

history.json
  生成履歴
```

初期版では、現在端末の画面サイズに合わせた縦長画像を適用する。
スクロール壁紙向けの横幅拡張は将来対応とする。

## 壁紙適用仕様

Android版では `WallpaperManager` を使って壁紙を適用する。

### 適用先

ユーザーは以下から適用先を選択できる。

```kotlin
enum class WallpaperApplyTarget {
    Home,
    Lock,
    HomeAndLock
}
```

### 方針

- ホーム画面への適用を基本機能とする。
- ロック画面への適用も提供する。
- 端末やOS、メーカー独自実装によりロック画面適用が失敗する場合は、失敗として履歴に残す。
- 壁紙適用に失敗しても、生成画像の保存に成功していれば画像は保持する。
- 壁紙適用失敗時は、写真保存または共有から手動設定できるように案内する。

### WallpaperServiceの責務

- 生成画像の存在確認
- 画像ファイルの読み込み
- 端末の画面サイズ取得
- 適用先サイズの決定
- リサイズ
- センタークロップ
- 必要に応じた圧縮/再保存
- ホーム画面壁紙への適用
- ロック画面壁紙への適用
- ホーム画面とロック画面の両方への適用
- 写真/ギャラリー保存
- 共有シート表示
- 適用失敗時のエラー返却

## スケジュール仕様

### RunsPerDay

`RunsPerDay` は、1日に自動生成を試みる回数を表す。

```text
RunsPerDay = 1日あたりの自動生成回数
```

`RunsPerDay` は分単位の更新間隔ではない。
例えば `RunsPerDay = 4` の場合は、1日を4つのスロットに分け、各スロットが未処理なら生成を試みる。

### 選択肢

```text
1, 2, 3, 4, 6, 8, 12, 24
```

表示例:

```text
1回/日
2回/日
3回/日
4回/日
6回/日
8回/日
12回/日
24回/日
```

### スロット間隔

| RunsPerDay | スロット間隔 |
|---:|---:|
| 1 | 24時間 |
| 2 | 12時間 |
| 3 | 8時間 |
| 4 | 6時間 |
| 6 | 4時間 |
| 8 | 3時間 |
| 12 | 2時間 |
| 24 | 1時間 |

### 定期生成の判定

定期生成では、現在時刻に対応するスケジュールスロットがすでに処理済みかを確認する。

```text
1. RunsPerDay から当日のスケジュールスロット一覧を作る
2. 現在時刻以前の最新スロットを取得する
3. そのスロット以降に成功履歴があれば生成しない
4. そのスロット以降に成功履歴がなければ生成を試みる
```

擬似コード:

```text
latestSlot = GetLatestScheduledSlotAtOrBefore(now, runsPerDay)
lastSuccessfulGeneratedAt = 最後に成功した生成時刻

if lastSuccessfulGeneratedAt >= latestSlot:
    skip
else:
    generate
```

### TaskSchedulerService / WorkManager登録

Android版でもクラス名は `TaskSchedulerService` とする。
Windows版ではWindows Task Schedulerを扱うが、Android版では内部で `WorkManager` を扱う。

初期版では、完了後に次回スロット向けの `OneTimeWorkRequest` を登録する方式を基本とする。
`PeriodicWorkRequest` は、RunsPerDayのスロット制と取りこぼし補完の扱いが複雑になりやすいため、初期版では必須にしない。

登録時には、`RunsPerDay` から次のスケジュールスロットを計算し、次回実行の目安として delay を設定する。

```text
nextSlot = GetNextScheduledSlotAfter(now, runsPerDay)
delay = nextSlot - now
```

WorkManagerは指定時刻ちょうどの実行を保証しない。
Androidの省電力制御、Doze、通信状態、充電状態、アプリ利用状況などにより実行時刻は前後する。

ユーザー向け文言は以下の意味にする。

```text
1日あたりの自動生成回数を指定します。
未処理の生成タイミングがあれば生成を試みます。
Androidの省電力制御により、実行時刻は前後する場合があります。
```

## 生成モード

### 手動生成

ユーザー操作で即時生成する。

```text
1. ユーザーが「今すぐ生成」を押す
2. GenerationCoordinatorを呼ぶ
3. ContextServiceが生成コンテキストを作る
4. GoogleAiServiceが画像を生成する
5. 画像をアプリ内に保存する
6. WallpaperServiceが必要に応じて画像を端末向けに調整する
7. WallpaperServiceが壁紙に適用する
8. HistoryServiceが履歴を保存する
9. 画面を更新する
```

手動生成では、ユーザーが明示的に開始しているため、画面上に処理状態を表示する。
処理中の多重実行は防止する。

### バックグラウンド定期生成

バックグラウンド定期生成は、`TaskSchedulerService` が登録した `WorkManager`、アプリ起動時、フォアグラウンド復帰時に実行可否を確認する。

```text
1. WorkManager、アプリ起動時、フォアグラウンド復帰時にチェックする
2. RunsPerDayから未処理スロットを判定する
3. 未処理スロットがなければスキップする
4. 未処理スロットがあれば1回だけ生成する
5. 成功・失敗・スキップを履歴に保存する
6. 必要に応じて通知する
7. TaskSchedulerServiceが次回スロット向けのWorkManagerを登録する
```

アプリ起動時・フォアグラウンド復帰時チェックは、WorkManagerが実行されなかった場合の取りこぼし補完として扱う。

### Foreground Worker

生成処理が長時間化する場合、またはOSによりバックグラウンド処理が中断されやすい場合は、`BackgroundGenerationWorker` をForeground Workerとして実行する。

Foreground Workerを使う場合は、生成中であることを示す通知を表示する。
初期版では必須ではないが、実機検証で生成失敗が多い場合に導入する。

## サービス構成

### AppConfigService

設定の読み書きを行う。

主な設定:

```text
- Google AI設定
- Google Calendar設定
- RSSソース
- ユーザープロンプト
- RunsPerDay
- 自動生成有効/無効
- 変化がなければスキップ
- 直前の壁紙をベースにするか
- 壁紙適用先
- 写真/ギャラリー保存設定
- 通知設定
- Wi-Fiのみ生成
- 低電力/省電力時は生成しない
```

### ContextService

画像生成に使う文脈を作る。

取得対象:

- Google Calendarの予定
- RSS/ニュース
- ユーザープロンプト

### GoogleAiService

Google AIに画像生成を依頼し、レスポンスとして受け取った画像を保存する。

方針:

- jobId方式は使わない。
- レスポンス受信後、即座にローカル保存する。
- 保存前に失敗した場合は生成失敗扱いにする。
- Android向けの縦長画像になるようにプロンプトを組み立てる。

### GenerationCoordinator

生成処理全体を統括する。

責務:

- 多重実行防止
- 手動生成
- スケジュールスロット判定
- コンテキスト取得
- 画像生成
- 画像保存
- `WallpaperService` 呼び出し
- `NotificationService` 呼び出し
- 履歴保存

UIとWorkerの両方からこのクラスを呼ぶ。
処理本体を画面側やWorker側に分散させない。

```text
UI:
  HomeViewModel -> GenerationCoordinator.RunAsync()

Worker:
  BackgroundGenerationWorker -> GenerationCoordinator.RunScheduledAsync()
```

Androidの実装言語はKotlinだが、メソッド名はWindows版の意図に合わせて以下に寄せる。

```text
GenerationCoordinator.RunAsync()
GenerationCoordinator.RunScheduledAsync()
```

### WallpaperService

生成画像を壁紙として利用できる状態にするサービス。

責務:

- 画像の存在確認
- 画像調整
- 壁紙適用先の判定
- ホーム画面壁紙への適用
- ロック画面壁紙への適用
- 写真/ギャラリー保存
- 共有シート表示
- 適用失敗時のエラー返却

画像調整用の独立した `ImagePrepareService` は初期版では作らない。

### HistoryService

生成履歴を保存する。

保存する情報:

```text
- 実行日時
- 成功/失敗/スキップ
- 原本画像パス
- 適用画像パス
- 使用した予定
- 使用したニュース
- 使用したプロンプト
- 適用先
- エラー概要
```

### TaskSchedulerService

定期生成の登録と解除を扱う。

Windows版の `TaskSchedulerService` と名前を揃える。
Android版では内部で `WorkManager` を使う。

責務:

- 次回スケジュールスロットの計算
- WorkManagerへの登録
- WorkManager登録解除
- 設定変更時の再登録
- アプリ起動時・フォアグラウンド復帰時の生成可否判定
- 端末再起動後の復旧

### NotificationService

通知を扱うAndroid固有サービス。
Windows版と対応する主要サービスではないが、Androidのバックグラウンド生成では通知が必要になるため独立させる。

通知種別:

- 生成完了通知
- 生成失敗通知
- 生成中通知（Foreground Worker使用時）

通知タップ時は、最新の生成画像詳細または該当履歴詳細を開く。

### BackgroundGenerationWorker

WorkManagerから起動されるAndroid固有の入口クラス。

責務は最小限にし、処理本体は `GenerationCoordinator` に委譲する。

```text
BackgroundGenerationWorker
  -> GenerationCoordinator.RunScheduledAsync()
  -> TaskSchedulerService.RegisterNextRun()
```

## 画面構成

### Home

- 最新生成画像プレビュー
- 今すぐ生成
- 壁紙に適用
- 適用先選択
  - ホーム画面
  - ロック画面
  - 両方
- 直近実行結果
- 次回自動生成の目安
- 写真/ギャラリーに保存
- 共有

### Data

- Google Calendar接続状態
- 取得対象カレンダー
- 直近予定
- RSSソース
- 取得ニュース
- ユーザープロンプト
- 生成に使う要素のプレビュー

### History

- 生成履歴一覧
- 成功/失敗/スキップ表示
- 画像プレビュー
- 使用した予定/ニュース
- 使用したプロンプト
- 再適用
- 同じ条件で再生成
- 写真/ギャラリーに保存
- 共有
- 削除

### Settings

- Google AI設定
- Google Calendar設定
- RSS設定
- 自動生成有効/無効
- RunsPerDay
- 変化がなければスキップ
- 直前の壁紙をベースにするか
- 既定の壁紙適用先
- 通知設定
- 写真/ギャラリー保存設定
- Wi-Fiのみ生成
- 低電力/省電力時は生成しない

## 初回セットアップウィザード

初回起動時には、Windows版/iOS版と同様にセットアップウィザードを表示する。

### ウィザード構成

```text
Step 1: ようこそ
  - WondayWallの説明
  - 自動壁紙生成の説明

Step 2: Google AI設定
  - APIキー入力
  - 接続確認

Step 3: Google Calendar連携
  - Google OAuth
  - カレンダー選択
  - 予定取得確認

Step 4: 興味・ニュース設定
  - ユーザープロンプト
  - RSSソース
  - キーワード

Step 5: 自動生成設定
  - RunsPerDay
  - Wi-Fiのみ
  - 低電力/省電力時スキップ
  - 通知権限
  - 壁紙適用先

Step 6: テスト生成
  - 生成
  - プレビュー
  - 壁紙適用テスト
```

実画面では、離脱を避けるために3〜4画面程度へ統合してもよい。
ただし、内部仕様としては上記の順に必要事項を満たす。

## 権限

### ネットワーク

以下に使う。

- Google AI画像生成
- Google Calendar取得
- RSS取得

### 壁紙設定権限

`WallpaperManager` による壁紙適用に使う。

### 通知権限

生成完了・生成失敗通知に使う。
通知設定を有効にしたタイミング、または自動生成を有効にしたタイミングで要求する。

### Google OAuth

Google Calendarの予定取得に使う。
取得した予定は生成コンテキストに反映する。

### 写真/ギャラリー保存

生成画像をギャラリーに保存するために使う。
初期版ではアプリ内保存を標準とし、ユーザー操作または設定で有効化された場合のみ `MediaStore` に保存する。

写真一覧の読み取りは初期版では要求しない。

### 共有

共有には `FileProvider` とAndroid共有シートを使う。

## AppConfig

Android版の設定モデルはWindows版の `AppConfig` を基準にし、Android固有設定だけを追加する。

```kotlin
data class AppConfig(
    val googleAiApiKey: String = "",
    val targetCalendarIds: List<String> = emptyList(),
    val rssSources: List<String> = emptyList(),
    val userPrompt: String = "",
    val runsPerDay: Int = 1,
    val useCurrentWallpaperAsBase: Boolean = false,
    val skipGenerationWhenNoChanges: Boolean = false,
    val updateLockScreen: Boolean = false,

    // Android固有
    val autoGenerationEnabled: Boolean = false,
    val applyTarget: WallpaperApplyTarget = WallpaperApplyTarget.Home,
    val saveToGallery: Boolean = false,
    val notifyOnSuccess: Boolean = true,
    val notifyOnFailure: Boolean = true,
    val generateOnlyOnWifi: Boolean = false,
    val skipOnBatterySaver: Boolean = true,
)
```

`googleAiApiKey`, `targetCalendarIds`, `rssSources`, `userPrompt`, `runsPerDay`, `useCurrentWallpaperAsBase`, `skipGenerationWhenNoChanges`, `updateLockScreen` はWindows版と同名にする。

## HistoryItem

Android版の `HistoryItem` もWindows版を基準にし、Androidで必要な情報だけを追加する。

```kotlin
data class HistoryItem(
    val executedAt: Instant,
    val isSuccess: Boolean,
    val errorSummary: String?,
    val appliedImagePath: String?,
    val usedCalendarEvents: List<CalendarEventItem>?,
    val usedNewsTopics: List<NewsTopicItem>?,
    val serviceTier: GoogleAiServiceTier,
    val isSkipped: Boolean = false,

    // Android固有
    val originalImagePath: String? = null,
    val usedPrompt: String? = null,
    val applyTarget: WallpaperApplyTarget? = null,
)
```

`CalendarEventItem`, `NewsTopicItem`, `PromptContext`, `GeneratedImageInfo`, `GoogleAiServiceTier` もWindows版と同名にする。

## 失敗時の扱い

### 生成失敗

```text
- 履歴に失敗を保存する
- エラー概要を保存する
- 必要なら通知する
- 次回再生成できるようにする
```

### 壁紙適用失敗

```text
- 生成画像は保存する
- 壁紙適用失敗として履歴に保存する
- エラー概要を保存する
- 必要なら通知する
- 写真保存または共有から手動設定できるように案内する
```

### スキップ

以下の場合は生成せず、スキップ扱いにする。

- 現在のスケジュールスロットがすでに処理済み
- 変化がなければスキップ設定が有効で、生成材料に変化がない
- Wi-Fiのみ生成が有効で、現在Wi-Fi接続ではない
- 低電力/省電力時スキップが有効で、省電力状態である

### 通信断・OS中断

```text
- 生成失敗扱いにする
- jobIdによる後追い取得はしない
- 次回実行時に再生成する
```

## 多重実行防止

手動生成とWorker生成が同時に走らないようにする。

初期版では、プロセス内の `Mutex` またはリポジトリ層の生成中フラグで防止する。
WorkManager側では、ユニークワーク名を使い、同種の定期生成が多重登録されないようにする。

```text
Unique work name:
  WondayWall.BackgroundGeneration
```

## 受け入れ基準

- 初回起動時にウィザードを完了できる。
- Google AI APIキーの接続確認ができる。
- Google Calendarの予定を取得できる。
- RSS/ニュースを取得できる。
- ユーザープロンプトを保存できる。
- 手動生成で縦長壁紙画像を生成できる。
- 生成画像をアプリ内に保存できる。
- ホーム画面壁紙に適用できる。
- ロック画面壁紙に適用できる端末では適用できる。
- ロック画面適用に失敗した場合は履歴と画面上で確認できる。
- RunsPerDayに基づいて未処理スロットを判定できる。
- `TaskSchedulerService` がWorkManagerを登録できる。
- WorkManagerから定期生成を試行できる。
- アプリ起動時・フォアグラウンド復帰時に未処理スロットを補完できる。
- 成功/失敗/スキップ履歴を保存できる。
- 生成完了/失敗通知を出せる。
- 生成中の多重実行を防止できる。
- 写真/ギャラリー保存ができる。
- Android共有シートで画像を共有できる。
- 主要クラス名がWindows版の `AppConfigService`、`ContextService`、`GoogleAiService`、`WallpaperService`、`GenerationCoordinator`、`HistoryService`、`TaskSchedulerService` と揃っている。

## 最終方針

WondayWall Android版は、ユーザーの予定・ニュース・ユーザープロンプトをもとにAndroid端末向けの縦長壁紙を生成し、ホーム画面またはロック画面へ自動適用するアプリとする。

Windows版の `GenerationCoordinator` 中心設計と、iOS版のモバイル向けバックグラウンド生成仕様を踏襲しつつ、Androidでは `WallpaperManager` による直接適用を提供する。

主要クラス名はWindows版に揃える。
定期生成は `RunsPerDay` のスロット制で管理し、`TaskSchedulerService` が内部で `WorkManager` を使って実行を試みる。
ただしAndroidの省電力制御により、実行時刻は保証しない。
