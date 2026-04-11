using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WondayWall.Utils;

/// <summary>ディスプレイサイズとアスペクト比の情報</summary>
public record DisplaySizeInfo(string Size, string AspectRatio);

internal static class DisplayHelper
{
    // gemini-3.1-flash-image-preview が 2K 解像度でサポートするサイズ一覧
    // (アスペクト比, "WxH", "W:H") の形式
    private static readonly (double Ratio, string Size, string AspectRatioLabel)[] SupportedSizes =
    [
        (1.0 / 8,  "768x6144",  "1:8"),
        (1.0 / 4,  "1024x4096", "1:4"),
        (2.0 / 3,  "1696x2528", "2:3"),
        (3.0 / 4,  "1792x2400", "3:4"),
        (4.0 / 5,  "1856x2304", "4:5"),
        (9.0 / 16, "1536x2752", "9:16"),
        (1.0 / 1,  "2048x2048", "1:1"),
        (5.0 / 4,  "2304x1856", "5:4"),
        (4.0 / 3,  "2400x1792", "4:3"),
        (3.0 / 2,  "2528x1696", "3:2"),
        (16.0 / 9, "2752x1536", "16:9"),
        (21.0 / 9, "3168x1344", "21:9"),
        (4.0 / 1,  "4096x1024", "4:1"),
        (8.0 / 1,  "6144x768",  "8:1"),
    ];

    /// <summary>現在のディスプレイ解像度に最も近いサポートサイズとアスペクト比を返す</summary>
    public static DisplaySizeInfo GetDisplayInfo()
    {
        var width = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
        var height = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);

        if (width <= 0 || height <= 0)
            return new DisplaySizeInfo("2752x1536", "16:9"); // フォールバック: 16:9

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
        return new DisplaySizeInfo(best.Size, best.AspectRatioLabel);
    }

    /// <summary>後方互換性のためサイズ文字列のみを返すラッパー</summary>
    public static string GetClosestSupportedSize() => GetDisplayInfo().Size;
}
