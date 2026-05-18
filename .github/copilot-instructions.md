このリポジトリの実装ルールの正本は `/AGENTS.md` です。

コードを実装・修正するときは、必ず `/AGENTS.md` に従ってください。

プラットフォーム別ルールは `.github/instructions/*.instructions.md` に分割しています。
- .NET版(Win版): `dotnet-win.instructions.md`
- iOS版: `ios.instructions.md`
- Android版: `android.instructions.md`

それぞれの instruction file は `applyTo` に一致するファイルを編集する場合のみ読み込まれます。
