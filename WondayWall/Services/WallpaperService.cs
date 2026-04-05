using System.IO;
using System.Runtime.InteropServices;

namespace WondayWall.Services;

public class WallpaperService
{
    private const int SpiSetdeskwallpaper = 0x0014;
    private const int SpifUpdateinifile = 0x01;
    private const int SpifSendchange = 0x02;

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int SystemParametersInfo(
        int uAction, int uParam, string lpvParam, int fuWinIni);

    public void SetWallpaper(string imagePath)
    {
        if (string.IsNullOrWhiteSpace(imagePath))
            throw new ArgumentException("Image path must not be empty.", nameof(imagePath));

        if (!File.Exists(imagePath))
            throw new FileNotFoundException("Wallpaper image not found.", imagePath);

        var fullPath = Path.GetFullPath(imagePath);
        SystemParametersInfo(
            SpiSetdeskwallpaper,
            0,
            fullPath,
            SpifUpdateinifile | SpifSendchange);
    }
}
