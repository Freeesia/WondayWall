using System.IO;
using Windows.Win32.UI.Shell;

namespace WondayWall.Services;

public class WallpaperService
{
    /// <summary>IDesktopWallpaper を使って全モニターに壁紙を適用する</summary>
    public unsafe void SetWallpaper(string imagePath)
    {
        if (string.IsNullOrWhiteSpace(imagePath))
            throw new ArgumentException("Image path must not be empty.", nameof(imagePath));

        if (!File.Exists(imagePath))
            throw new FileNotFoundException("Wallpaper image not found.", imagePath);

        var fullPath = Path.GetFullPath(imagePath);
        // Windows 8.0 以降でサポートされる IDesktopWallpaper を使用
        // このアプリは Windows 専用のため警告を抑制
#pragma warning disable CA1416
        var wallpaper = (IDesktopWallpaper)new DesktopWallpaper();
        // monitorID に null (既定モニター) を指定すると全モニターに適用
        fixed (char* pathPtr = fullPath)
        {
            wallpaper.SetWallpaper(default, pathPtr);
        }
#pragma warning restore CA1416
    }
}
