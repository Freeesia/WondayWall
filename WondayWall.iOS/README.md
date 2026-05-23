# WondayWall iOS

ユーザーの予定・ニュース・ユーザープロンプトをもとに iPhone 向けの壁紙候補画像を自動生成する iOS アプリ。

## 必要環境

- Xcode 16.0 以降
- XcodeGen 2.45.4 以降
- iOS 17.0 以降（実機またはシミュレーター）
- Google Cloud プロジェクト（Calendar API 有効化済み）
- Google AI Studio API キー

## ビルド方法

1. `cd WondayWall.iOS`
2. `xcodegen generate`
3. `WondayWall.xcodeproj` を Xcode で開く
4. ターゲットデバイスを選択してビルド・実行

## TestFlight Preview CI

GitHub Actions の `iOS TestFlight` workflow で、Preview アプリを TestFlight Internal Testing へアップロードする。

- 実行方法: `workflow_dispatch` または `main` 向け同一リポジトリ内 PR
- fork PR: 署名資材と App Store Connect API Key を使わず、アップロード job をスキップ
- Runner: `macos-26`（App Store Connect upload に必要な iOS 26 SDK / Xcode 26 を使う）
- Environment: `testflight-pr`（Required reviewers 承認後に配布へ進む）
- Bundle ID: `com.studiofreesia.wondaywall.preview`
- TestFlight group: `PR Preview Testers`（グループ設定で「Xcodeビルドを自動配信」を有効化）
- Version / build: `0.0.0` / `${{ github.run_number }}.${{ github.run_attempt }}`

必要な Environment secrets:

```text
ASC_KEY_ID
ASC_ISSUER_ID
ASC_KEY_P8
APPSTORE_CERTIFICATE_BASE64
APPSTORE_CERTIFICATE_PASSWORD
APPSTORE_PROVISIONING_PROFILE_BASE64
KEYCHAIN_PASSWORD
```

CI では `xcodegen generate` で `WondayWall.xcodeproj` を生成し、`Config/Preview.xcconfig` を include した一時 xcconfig で build number を上書きして Release archive を作成する。IPA は TestFlight Internal Only としてアップロードし、内部グループへの配信は App Store Connect の自動配信設定に任せる。アップロード成功後は Actions Summary に PR、commit、build number、TestFlight インストール手順を出力する。

## 初期設定

1. **Google AI API キー**: [Google AI Studio](https://aistudio.google.com) で取得し、設定画面に入力する
2. **Google Calendar 連携**: 設定画面の「Google Calendar と連携」から OAuth 認証を行う
3. **RSS ソース**: 必要に応じてニュースフィードの URL を追加する

## アーキテクチャ

```
WondayWall.iOS/
├── project.yml                 # XcodeGen プロジェクト定義
├── WondayWall.xcodeproj/       # XcodeGen 生成物（Package.resolved のみ管理対象）
└── WondayWall/
    ├── App/                    # エントリポイント・DI コンテナ
    │   ├── WondayWallApp.swift  # @main エントリポイント
    │   ├── AppDelegate.swift   # BGTask 登録・通知デリゲート
    │   └── AppEnvironment.swift # サービス DI コンテナ (@MainActor)
    ├── Models/                 # データモデル
    ├── Services/               # ビジネスロジック
    ├── Views/                  # SwiftUI ビュー + ViewModel
    │   ├── ContentView.swift   # TabView
    │   ├── Home/               # 壁紙プレビュー・生成ボタン
    │   ├── DataView/           # カレンダー・ニュース確認
    │   ├── History/            # 生成履歴
    │   └── Settings/           # 設定
    ├── Utils/                  # ユーティリティ
    └── Resources/              # アセット・Info.plist
```

### サービス一覧

| サービス | 役割 |
|---------|------|
| `AppConfigService` | 設定の読み書き（`Application Support/WondayWall/config.json`） |
| `HistoryService` | 生成履歴の読み書き（`history.json`） |
| `ContextService` | Google Calendar + RSS からプロンプトコンテキストを構築 |
| `GoogleAiService` | Gemini API で壁紙画像を生成 |
| `WallpaperService` | 写真ライブラリ保存・共有シート・設定手順表示 |
| `GenerationCoordinator` | 生成フロー全体の統括（`actor` による多重実行防止） |
| `BackgroundTaskService` | `BGProcessingTask` によるバックグラウンド定期生成 |
| `ForegroundBackgroundTaskService` | 手動生成中のバックグラウンド移行対応 |
| `NotificationService` | 生成完了・失敗通知 |

## 注意事項

- iOS では通常アプリから壁紙を直接変更できないため、写真ライブラリ保存と共有で対応
- バックグラウンド定期生成は iOS のバックグラウンド実行制限の影響を受ける
- OAuth トークンは Keychain に保存される
- 生成画像は `Application Support/WondayWall/wallpapers/` に保存される
