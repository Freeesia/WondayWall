using System.IO;

namespace WondayWall.Utils;

public static class PathUtility
{
    private const string AppDirectoryName =
#if DEBUG
        "WondayWall-debug";
#else
        "WondayWall";
#endif

    public static string AppDataDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "StudioFreesia",
        AppDirectoryName);
}
