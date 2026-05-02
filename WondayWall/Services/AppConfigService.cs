using System.IO;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class AppConfigService
{
    private static readonly string ConfigFilePath =
        Path.Combine(PathUtility.AppDataDirectory, "config.json");

    private AppConfig? _current;

    public bool HasSavedConfig => File.Exists(ConfigFilePath);

    public AppConfig Current => _current ??= Load();

    public AppConfig Load()
    {
        _current = JsonFileHelper.Load<AppConfig>(ConfigFilePath) ?? new();
        return _current;
    }

    public void Save(AppConfig config)
    {
        _current = config;
        JsonFileHelper.Save(ConfigFilePath, config);
    }

    /// <summary>設定に基づく壁紙保存フォルダパスを返す</summary>
    public string GetWallpaperSaveDirectory()
        => PathUtility.GetWallpaperDirectory(Current.SaveToOneDrive);

    /// <summary>
    /// 壁紙画像を移行先フォルダへコピーする。既存ファイルはスキップする。
    /// </summary>
    public void MigrateWallpaperImages(bool toOneDrive)
    {
        var sourceDir = PathUtility.GetWallpaperDirectory(!toOneDrive);
        var targetDir = PathUtility.GetWallpaperDirectory(toOneDrive);

        if (!Directory.Exists(sourceDir))
            return;

        Directory.CreateDirectory(targetDir);

        foreach (var sourceFile in Directory.EnumerateFiles(sourceDir))
        {
            var destFile = Path.Combine(targetDir, Path.GetFileName(sourceFile));
            if (!File.Exists(destFile))
            {
                try
                {
                    File.Copy(sourceFile, destFile);
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"壁紙のコピーに失敗しました '{sourceFile}' -> '{destFile}': {ex.Message}");
                }
            }
        }
    }
}
