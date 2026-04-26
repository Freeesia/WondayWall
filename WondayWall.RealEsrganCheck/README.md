# WondayWall.RealEsrganCheck

Real-ESRGAN-ncnn-vulkan の実行確認用 console プロジェクトです。

```powershell
dotnet run --project WondayWall.RealEsrganCheck -- "C:\path\to\input.png"
```

- Real-ESRGAN の取得には既存の `ToolDownloadService` を使います。
- アップスケールには既存の `UpscaleService` の Real-ESRGAN 実行処理を使います。
- Lanczos fallback は使いません。
- Real-ESRGAN が失敗した場合、終了コード `1` で終了します。
- 成功時は出力パスと入力/出力サイズを表示します。
