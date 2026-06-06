# WondayWall

[日本語](README.md) | [English](README.en.md)

予定やニュース、興味キーワードをもとに壁紙画像を生成する Windows / iOS / Android 向けパーソナル壁紙アプリです。

WondayWall は Gemini API を使って、その日の予定や関心に合わせた壁紙候補を生成します。

## 画面イメージ

以下は Windows 版の画面イメージです。

<p align="center">
  <img src="assets/store_hero.png" alt="WondayWall が生成した壁紙イメージ" width="100%">
</p>

<p align="center">
  <img src="assets/store_screenshot_home.png" alt="ホーム画面" width="32%">
  <img src="assets/store_screenshot_data.png" alt="データ画面" width="32%">
  <img src="assets/store_screenshot_settings.png" alt="設定画面" width="32%">
</p>

<p align="center">
  <img src="assets/store_screenshot_wallpaper_variations.png" alt="予定やニュースに合わせた壁紙バリエーション" width="100%">
</p>

## 対応状況

| OS | 対応内容 |
|----|----------|
| Windows | デスクトップ版。GUI と CLI を備え、Task Scheduler による定期生成に対応 |
| iOS | iPhone 向け。iOS の制約により壁紙の直接変更は行わず、写真保存・共有・設定手順表示で対応 |
| Android | Android 端末向け。ホーム画面・ロック画面壁紙への適用に対応 |

## 必要な環境

| OS | 必要なもの |
|----|------------|
| Windows | Windows 10 / 11、[.NET 10 Runtime](https://dotnet.microsoft.com/download/dotnet/10.0)、Google AI API キー、Google Calendar 連携 |
| iOS | iOS 17.0 以降、Google AI API キー、カレンダー・写真・通知への許可 |
| Android | Android 8.0 以降、Google AI API キー、カレンダー・通知・壁紙設定への許可 |

## セットアップ

### Windows

1. [リリースページ](https://github.com/Freeesia/WondayWall/releases/latest)から `WondayWall-(バージョン).msi` をダウンロード
2. ダウンロードした MSI を実行し、インストーラーの案内に従ってインストール
3. インストールした WondayWall を起動するとセットアップ画面が表示される
4. **Google AI API キー** を設定
5. **Google Calendar** の認証を行う
6. 興味キーワードと RSS フィード URL を登録
7. 「今すぐ生成」で動作確認

定期実行するには、アプリの設定画面で **実行頻度** を選び登録します。

### iOS

1. アプリを起動し、**Google AI API キー** を設定
2. iOS カレンダーへのアクセスを許可し、参照するカレンダーを選択
3. 興味キーワードと RSS フィード URL を登録
4. 写真ライブラリ保存や通知を使う場合は、必要な許可を付与
5. 「今すぐ生成」で壁紙候補を生成

iOS では通常のアプリからホーム画面・ロック画面の壁紙を直接変更できないため、生成画像を写真ライブラリへ保存し、共有またはアプリ内の手順表示に従って手動で壁紙に設定します。

### Android

1. アプリを起動し、**Google AI API キー** を設定
2. 端末カレンダーへの読み取り権限を許可し、参照するカレンダーを選択
3. 興味キーワードと RSS フィード URL を登録
4. 通知やギャラリー保存に必要な許可を付与
5. 「今すぐ生成」で壁紙を生成し、ホーム画面へ適用

## 機能

| 機能 | Windows | iOS | Android |
|------|---------|-----|---------|
| Gemini による壁紙生成 | 対応 | 対応 | 対応 |
| 手動生成 | GUI から即時生成 | アプリから即時生成 | アプリから即時生成 |
| 定期生成 | 対応 | 対応 | 対応 |
| カレンダー取得 | Google カレンダー | カレンダー | カレンダー |
| RSS ニュース取得 | 対応 | 対応 | 対応 |
| 壁紙適用 | デスクトップ壁紙、設定によりロック画面 | 自動適用不可。写真保存・共有・設定手順表示 | ホーム画面、設定によりロック画面にも追加適用 |
| 生成履歴 | 対応 | 対応 | 対応 |
| CLI | `run-once` / `generate` / `check-*` | 非対応 | 非対応 |

## CLI コマンド（Windows）

```powershell
WondayWall.exe run-once          # 設定した実行頻度に応じた現在のスケジュール枠が未処理なら1回生成して終了（Task Scheduler 向け）
WondayWall.exe generate          # 即時生成
WondayWall.exe check-calendar    # Google Calendar 取得のみ確認
WondayWall.exe check-news        # ニュース取得のみ確認
WondayWall.exe check-google-ai   # Gemini API 接続確認
```

## 保存データ

設定、生成履歴、生成画像、およびカレンダー連携の認証情報は、各OSのセキュアなローカル領域に保存されます。

- **API キー**: 各OSのセキュアな保管機能（Windows 資格情報マネージャー、iOS Keychain、Android 暗号化 DataStore 相当）で暗号化されて保管されます。
- **写真ライブラリ**: モバイルOS（iOS/Android）では、設定を有効にすることで生成された画像を端末の写真ライブラリやギャラリーにも保存できます。

## スケジュール

全プラットフォーム共通で、自動更新の頻度（週1回 / 週2回 / 週3回 / 1日1回 / 1日3回）を設定できます。

※モバイルOS（iOS/Android）のバックグラウンド実行はOSによる制御を受けるため、指定時刻での実行は保証されません。未処理分はアプリ起動時やフォアグラウンド復帰時に補完されます。

## 開発者向け

```sh
git clone https://github.com/Freeesia/WondayWall.git
cd WondayWall/WondayWall
dotnet build
```

プラットフォーム別の詳細は次のドキュメントを参照してください。

- [.NET / Windows: dev.md](https://github.com/Freeesia/WondayWall/blob/main/dev.md)
- [iOS: dev_ios.md](https://github.com/Freeesia/WondayWall/blob/main/dev_ios.md)
- [Android: dev_android.md](https://github.com/Freeesia/WondayWall/blob/main/dev_android.md)

## 法的情報

[プライバシーポリシー](PrivacyPolicy.md)

[利用規約](Terms_of_Use.md)

[生成画像の利用について](GeneratedImageUsage.md)

## ライセンス

[MIT License](https://github.com/Freeesia/WondayWall/blob/main/LICENSE)
