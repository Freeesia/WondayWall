using System.IO;
using Microsoft.Extensions.Logging;
using Windows.Foundation.Metadata;
using Windows.Storage;
using Windows.System.UserProfile;
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

    /// <summary>デスクトップ壁紙を適用し、必要に応じてロック画面も更新する</summary>
    public async Task SetWallpaperAsync(string imagePath, bool updateLockScreen, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();

        var fullPath = ValidateImagePath(imagePath);
        SetDesktopWallpaperCore(fullPath);

        if (!updateLockScreen)
            return;

        await TrySetLockScreenAsync(fullPath, ct);
    }

    private static string ValidateImagePath(string imagePath)
    {
        if (string.IsNullOrWhiteSpace(imagePath))
            throw new ArgumentException("Image path must not be empty.", nameof(imagePath));

        if (!File.Exists(imagePath))
            throw new FileNotFoundException("Wallpaper image not found.", imagePath);

        return Path.GetFullPath(imagePath);
    }

    private unsafe void SetDesktopWallpaperCore(string fullPath)
    {
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

    private static bool IsLockScreenSupported()
        => OperatingSystem.IsWindows()
        && ApiInformation.IsTypePresent("Windows.System.UserProfile.LockScreen")
        && ApiInformation.IsMethodPresent("Windows.System.UserProfile.LockScreen", nameof(LockScreen.SetImageFileAsync));

    private async Task TrySetLockScreenAsync(string fullPath, CancellationToken ct)
    {
        if (!IsLockScreenSupported())
        {
            logger.LogInformation("ロック画面の更新はこの環境ではサポートされていないため、デスクトップ壁紙のみ更新します");
            return;
        }

        try
        {
            ct.ThrowIfCancellationRequested();
            var file = await StorageFile.GetFileFromPathAsync(fullPath);
            await LockScreen.SetImageFileAsync(file);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "ロック画面の更新に失敗したため、デスクトップ壁紙のみ更新しました");
        }
    }
}
