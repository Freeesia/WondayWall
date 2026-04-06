using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WondayWall.Utils;

internal static class DisplayHelper
{
    private const string DefaultResolution = "1920x1080";

    public static string GetPrimaryScreenSize()
    {
        var width = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
        var height = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);
        if (width <= 0 || height <= 0)
            return DefaultResolution;
        return $"{width}x{height}";
    }
}
