using System.IO;
using Microsoft.Extensions.Logging;
using Windows.Win32.UI.Shell;
using WindowsDesktop;

namespace WondayWall.Services;

public class WallpaperService
{
    private readonly IDesktopWallpaper _wallpaper = (IDesktopWallpaper)new DesktopWallpaper();
    private readonly ILogger<WallpaperService> logger;

    public WallpaperService(ILogger<WallpaperService> logger)
    {
        this.logger = logger;
        VirtualDesktop.Configure(new()
        {
            CompiledAssemblySaveDirectory = new(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "StudioFreesia",
#if DEBUG
                "WondayWall-debug",
#else
                "WondayWall",
#endif
                "assemblies")),
        });
    }

    /// <summary>すべての仮想デスクトップに壁紙を適用する</summary>
    public unsafe void SetWallpaper(string imagePath)
    {
        if (string.IsNullOrWhiteSpace(imagePath))
            throw new ArgumentException("Image path must not be empty.", nameof(imagePath));

        if (!File.Exists(imagePath))
            throw new FileNotFoundException("Wallpaper image not found.", imagePath);

        var fullPath = Path.GetFullPath(imagePath);

        // 仮想デスクトップ API が使用可能な場合は全仮想デスクトップに壁紙を適用
        if (VirtualDesktop.IsSupported)
        {
            try
            {
                VirtualDesktop.UpdateWallpaperForAllDesktops(fullPath);
                return;
            }
            catch (Exception ex)
            {
                // 仮想デスクトップ API の失敗時は IDesktopWallpaper へフォールバック
                logger.LogWarning(ex, "仮想デスクトップ API での壁紙設定に失敗しました。IDesktopWallpaper にフォールバックします");
            }
        }

        // 仮想デスクトップ API が使用できない場合は全モニターに適用（フォールバック）
        fixed (char* pathPtr = fullPath)
        {
            _wallpaper.SetWallpaper(default, pathPtr);
        }
    }
}
