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

    /// <summary>ローカルの壁紙保存フォルダパス</summary>
    public static string LocalWallpaperDirectory => Path.Combine(AppDataDirectory, "wallpapers");

    /// <summary>OneDrive 配下の壁紙保存フォルダパス</summary>
    public static string OneDriveWallpaperDirectory
    {
        get
        {
            // OneDrive 環境変数（Windows で OneDrive がインストールされている場合に設定される）
            var oneDrivePath = Environment.GetEnvironmentVariable("OneDrive");
            if (string.IsNullOrEmpty(oneDrivePath))
                oneDrivePath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    "OneDrive");
            return Path.Combine(oneDrivePath, "WondayWall", "wallpapers");
        }
    }

    /// <summary>設定に基づく壁紙保存フォルダパスを返す</summary>
    public static string GetWallpaperDirectory(bool saveToOneDrive)
        => saveToOneDrive ? OneDriveWallpaperDirectory : LocalWallpaperDirectory;
}
