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

    /// <summary>壁紙保存フォルダパス（MyPictures フォルダ配下。OneDrive 有効時は自動的に OneDrive にも保存される）</summary>
    public static string WallpaperDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.MyPictures),
        AppDirectoryName);
}
