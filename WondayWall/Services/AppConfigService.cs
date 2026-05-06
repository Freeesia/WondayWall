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
        Migrate(_current);
        return _current;
    }

    public void Save(AppConfig config)
    {
        _current = config;
        JsonFileHelper.Save(ConfigFilePath, config);
    }

    /// <summary>旧バージョンの設定フィールドを新しいフィールドへ移行する</summary>
    private static void Migrate(AppConfig config)
    {
        // RunsPerDay が設定されていた旧バージョンからのマイグレーション
        if (config.RunsPerDay.HasValue)
        {
            config.Schedule = ScheduleHelper.MigrateFromRunsPerDay(config.RunsPerDay.Value);
            config.RunsPerDay = null;
        }
    }
}
