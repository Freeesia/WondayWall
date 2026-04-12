using System.IO;
using Windows.Win32.UI.Shell;

namespace WondayWall.Services;

public class WallpaperService
{
    private readonly IDesktopWallpaper _wallpaper;

    /// <summary>DI登録でのみ呼び出される内部コンストラクター</summary>
    internal WallpaperService(IDesktopWallpaper wallpaper)
    {
        _wallpaper = wallpaper;
    }

    /// <summary>IDesktopWallpaper を使って全モニターに壁紙を適用する</summary>
    public unsafe void SetWallpaper(string imagePath)
    {
        if (string.IsNullOrWhiteSpace(imagePath))
            throw new ArgumentException("Image path must not be empty.", nameof(imagePath));

        if (!File.Exists(imagePath))
            throw new FileNotFoundException("Wallpaper image not found.", imagePath);

        var fullPath = Path.GetFullPath(imagePath);
        // monitorID に null (既定モニター) を指定すると全モニターに適用
#pragma warning disable CA1416
        fixed (char* pathPtr = fullPath)
        {
            _wallpaper.SetWallpaper(default, pathPtr);
        }
#pragma warning restore CA1416
    }
}
