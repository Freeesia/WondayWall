using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WondayWall.Utils;

internal static class DisplayHelper
{
    // Supported image sizes for gemini-3.1-flash-image-preview at 2K resolution
    // aspect ratio (W:H) => "WxH"
    private static readonly (double Ratio, string Size)[] SupportedSizes =
    [
        (1.0 / 8,  "768x6144"),
        (1.0 / 4,  "1024x4096"),
        (2.0 / 3,  "1696x2528"),
        (3.0 / 4,  "1792x2400"),
        (4.0 / 5,  "1856x2304"),
        (9.0 / 16, "1536x2752"),
        (1.0 / 1,  "2048x2048"),
        (5.0 / 4,  "2304x1856"),
        (4.0 / 3,  "2400x1792"),
        (3.0 / 2,  "2528x1696"),
        (16.0 / 9, "2752x1536"),
        (21.0 / 9, "3168x1344"),
        (4.0 / 1,  "4096x1024"),
        (8.0 / 1,  "6144x768"),
    ];

    public static string GetClosestSupportedSize()
    {
        var width = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
        var height = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);

        if (width <= 0 || height <= 0)
            return "2752x1536"; // fallback to 16:9

        var ratio = (double)width / height;

        var best = SupportedSizes[0];
        var bestDiff = Math.Abs(ratio - best.Ratio);
        foreach (var entry in SupportedSizes.AsSpan(1))
        {
            var diff = Math.Abs(ratio - entry.Ratio);
            if (diff < bestDiff)
            {
                best = entry;
                bestDiff = diff;
            }
        }
        return best.Size;
    }
}
