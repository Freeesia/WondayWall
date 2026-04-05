using System.IO;
using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WondayWall.Services;

public class WallpaperService
{
    public unsafe void SetWallpaper(string imagePath)
    {
        if (string.IsNullOrWhiteSpace(imagePath))
            throw new ArgumentException("Image path must not be empty.", nameof(imagePath));

        if (!File.Exists(imagePath))
            throw new FileNotFoundException("Wallpaper image not found.", imagePath);

        var fullPath = Path.GetFullPath(imagePath);
        fixed (char* pathPtr = fullPath)
        {
            PInvoke.SystemParametersInfo(
                SYSTEM_PARAMETERS_INFO_ACTION.SPI_SETDESKWALLPAPER,
                0,
                pathPtr,
                SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS.SPIF_UPDATEINIFILE |
                SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS.SPIF_SENDCHANGE);
        }
    }
}
