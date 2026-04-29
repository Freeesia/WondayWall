using System.IO;

namespace WondayWall.Utils;

public static class PathUtility
{
    public static string AppDataDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "StudioFreesia",
        "WondayWall");
}
