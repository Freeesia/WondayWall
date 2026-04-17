using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;
using Windows.Foundation.Metadata;
using Windows.Storage;
using Windows.System.UserProfile;
using WindowsDesktop;

namespace WondayWall.Services;

public class WallpaperService
{
    private const int SpiSetDesktopWallpaper = 0x0014;
    private const int SpifUpdateIniFile = 0x0001;
    private const int SpifSendWinIniChange = 0x0002;

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
    public void SetWallpaper(string imagePath)
    {
        var fullPath = ValidateImagePath(imagePath);
        SetDesktopWallpaperCore(fullPath);
    }

    /// <summary>デスクトップ壁紙を適用し、必要に応じてロック画面も更新する</summary>
    public async Task<string?> SetWallpaperAsync(string imagePath, bool updateLockScreen, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();

        var fullPath = ValidateImagePath(imagePath);
        SetDesktopWallpaperCore(fullPath);

        if (!updateLockScreen)
            return null;

        return await TrySetLockScreenAsync(fullPath, ct);
    }

    private static string ValidateImagePath(string imagePath)
    {
        if (string.IsNullOrWhiteSpace(imagePath))
            throw new ArgumentException("Image path must not be empty.", nameof(imagePath));

        if (!File.Exists(imagePath))
            throw new FileNotFoundException("Wallpaper image not found.", imagePath);

        return Path.GetFullPath(imagePath);
    }

    private void SetDesktopWallpaperCore(string fullPath)
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
                logger.LogWarning(ex, "仮想デスクトップ API での壁紙設定に失敗しました。SystemParametersInfo にフォールバックします");
            }
        }

        if (!SystemParametersInfo(SpiSetDesktopWallpaper, 0, fullPath, SpifUpdateIniFile | SpifSendWinIniChange))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Failed to set desktop wallpaper.");
    }

    private static bool IsLockScreenSupported()
    {
        return OperatingSystem.IsWindows()
            && ApiInformation.IsTypePresent("Windows.System.UserProfile.LockScreen")
            && ApiInformation.IsMethodPresent("Windows.System.UserProfile.LockScreen", nameof(LockScreen.SetImageFileAsync));
    }

    private async Task<string?> TrySetLockScreenAsync(string fullPath, CancellationToken ct)
    {
        if (!IsLockScreenSupported())
        {
            logger.LogInformation("ロック画面の更新はこの環境ではサポートされていないため、デスクトップ壁紙のみ更新します");
            return "ロック画面の更新はこの環境ではサポートされていないため、デスクトップ壁紙のみ更新しました。";
        }

        try
        {
            ct.ThrowIfCancellationRequested();
            var file = await StorageFile.GetFileFromPathAsync(fullPath);
            await LockScreen.SetImageFileAsync(file);
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "ロック画面の更新に失敗したため、デスクトップ壁紙のみ更新しました");
            return $"ロック画面の更新に失敗したため、デスクトップ壁紙のみ更新しました: {ex.Message}";
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
}
