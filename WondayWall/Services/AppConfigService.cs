using System.IO;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class AppConfigService
{
    private static readonly string ConfigDirectory =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WondayWall");

    private static readonly string ConfigFilePath =
        Path.Combine(ConfigDirectory, "config.json");

    private AppConfig? _current;

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

    public void Save() => Save(_current);
}
