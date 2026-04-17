using Windows.Foundation.Metadata;
using Windows.Storage;
using Windows.System.UserProfile;

namespace WondayWall.Services;

public class LockScreenWallpaperService(ILogger<LockScreenWallpaperService> logger)
{
    public bool IsSupported()
    {
        return OperatingSystem.IsWindows()
            && ApiInformation.IsTypePresent("Windows.System.UserProfile.LockScreen")
            && ApiInformation.IsMethodPresent("Windows.System.UserProfile.LockScreen", nameof(LockScreen.SetImageFileAsync));
    }

    public async Task<string?> TryApplyAsync(string imagePath, CancellationToken ct = default)
    {
        if (!IsSupported())
        {
            logger.LogInformation("ロック画面の更新はこの環境ではサポートされていないため、デスクトップ壁紙のみ更新します");
            return "ロック画面の更新はこの環境ではサポートされていないため、デスクトップ壁紙のみ更新しました。";
        }

        try
        {
            ct.ThrowIfCancellationRequested();
            var file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(imagePath));
            await LockScreen.SetImageFileAsync(file);
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "ロック画面の更新に失敗したため、デスクトップ壁紙のみ更新しました");
            return $"ロック画面の更新に失敗したため、デスクトップ壁紙のみ更新しました: {ex.Message}";
        }
    }
}
