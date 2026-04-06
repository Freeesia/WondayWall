using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WondayWall.Utils;

internal static class DisplayHelper
{
    public static string GetPrimaryScreenSize()
    {
        var width = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
        var height = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);
        if (width <= 0 || height <= 0)
            return "1920x1080";
        return $"{width}x{height}";
    }
}
