---
applyTo: "WondayWall/**/*.{cs,xaml,csproj,resx,props,targets,json}"
---

# .NET版（Win版）実装ルール

- Windows 向け .NET 実装の詳細は `/dev.md` を正本として従う。
- `Program.cs` のハイブリッド構成（GUI/CLI）を維持する。
- `<StartupObject>WondayWall.Program</StartupObject>` を削除しない。
- `EnableWindowsTargeting=true` は Linux CI ビルド互換のため削除しない。
- サービスは `AddSingleton`、View/ViewModel は `AddTransient` を維持する。
