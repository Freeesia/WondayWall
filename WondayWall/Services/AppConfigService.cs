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

    private AppConfig _current = new();

    public AppConfig Current => _current;

    public AppConfig Load()
    {
        _current = JsonFileHelper.Load<AppConfig>(ConfigFilePath) ?? CreateDefault();
        return _current;
    }

    public void Save(AppConfig config)
    {
        _current = config;
        JsonFileHelper.Save(ConfigFilePath, config);
    }

    public void Save() => Save(_current);

    private static AppConfig CreateDefault()
    {
        var defaultImagePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyPictures),
            "WondayWall");

        return new AppConfig
        {
            ImageSavePath = defaultImagePath,
            UpdateIntervalHours = 6,
            EnableLogging = true,
            ImageSize = "1920x1080",
        };
    }
}
