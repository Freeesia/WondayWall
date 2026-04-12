using GenerativeAI;
using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WondayWall.Utils;

/// <summary>ディスプレイサイズとアスペクト比、画像生成サイズの情報</summary>
/// <param name="Size">画像の解像度文字列 (例: "2752x1536")</param>
/// <param name="AspectRatio">アスペクト比文字列 (例: "16:9")</param>
/// <param name="ImageSize">Gemini API の画像サイズ区分 ("1K" / "2K" / "4K")</param>
public record DisplaySizeInfo(string Size, string AspectRatio, string ImageSize);

internal static class DisplayHelper
{
    // gemini-3.1-flash-image-preview がサポートするサイズ一覧 (各解像度ティア)
    // (アスペクト比率, ラベル, 1K, 2K, 4K) の形式
    private static readonly (double Ratio, string Label, string S1K, string S2K, string S4K)[] SupportedSizes =
    [
        (1.0 / 8,  "1:8",  "384x3072",  "768x6144",   "1536x12288"),
        (1.0 / 4,  "1:4",  "512x2048",  "1024x4096",  "2048x8192"),
        (2.0 / 3,  "2:3",  "848x1264",  "1696x2528",  "3392x5056"),
        (3.0 / 4,  "3:4",  "896x1200",  "1792x2400",  "3584x4800"),
        (4.0 / 5,  "4:5",  "928x1152",  "1856x2304",  "3712x4608"),
        (9.0 / 16, "9:16", "768x1376",  "1536x2752",  "3072x5504"),
        (1.0 / 1,  "1:1",  "1024x1024", "2048x2048",  "4096x4096"),
        (5.0 / 4,  "5:4",  "1152x928",  "2304x1856",  "4608x3712"),
        (4.0 / 3,  "4:3",  "1200x896",  "2400x1792",  "4800x3584"),
        (3.0 / 2,  "3:2",  "1264x848",  "2528x1696",  "5056x3392"),
        (16.0 / 9, "16:9", "1376x768",  "2752x1536",  "5504x3072"),
        (21.0 / 9, "21:9", "1584x672",  "3168x1344",  "6336x2688"),
        (4.0 / 1,  "4:1",  "2048x512",  "4096x1024",  "8192x2048"),
        (8.0 / 1,  "8:1",  "3072x384",  "6144x768",   "12288x1536"),
    ];

    /// <summary>現在のディスプレイ解像度に最も近いサポートサイズ・アスペクト比・画像サイズ区分を返す</summary>
    public static DisplaySizeInfo GetDisplayInfo()
    {
        var width = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
        var height = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);

        if (width <= 0 || height <= 0)
            return new DisplaySizeInfo("2752x1536", "16:9", ImageConfigValues.ImageSizes.Size2K); // フォールバック: 16:9 2K

        var ratio = (double)width / height;

        // アスペクト比に最も近いエントリーを選ぶ
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

        // ディスプレイの長辺からサイズ区分を決定 (Size1K / Size2K / Size4K)
        var maxDim = Math.Max(width, height);
        var (sizeValue, sizeStr) = maxDim >= 3840
            ? (ImageConfigValues.ImageSizes.Size4K, best.S4K)
            : maxDim >= 1920
            ? (ImageConfigValues.ImageSizes.Size2K, best.S2K)
            : (ImageConfigValues.ImageSizes.Size1K, best.S1K);

        return new DisplaySizeInfo(sizeStr, best.Label, sizeValue);
    }
}
