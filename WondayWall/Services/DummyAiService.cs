using System.IO;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class DummyAiService(AppConfigService configService)
{
    public async Task<List<NewsTopicItem>> BuildNewsTopicsAsync(CancellationToken ct = default)
    {
        var debugConfig = configService.Current.DebugConfig;
        if (debugConfig.DummyPromptDelaySeconds > 0)
            await Task.Delay(TimeSpan.FromSeconds(debugConfig.DummyPromptDelaySeconds), ct);

        var templates = new (string Title, string Summary)[]
        {
            ("ダミーニュース{n}: 週末の空模様と街イベントの見どころ", "週末に楽しめる屋外イベントと天気の変化をまとめたダミーニュースです。"),
            ("ダミーニュース{n}: 新しい生成AIツールが公開、制作ワークフローを短縮", "デザインや文章作成を支援する新機能の概要を紹介するダミーニュースです。"),
            ("ダミーニュース{n}: 夜景スポットでライトアップ企画が開始", "季節限定のライトアップと周辺のおすすめルートを扱うダミーニュースです。"),
            ("ダミーニュース{n}: 宇宙観測プロジェクトが新しい画像を公開", "星雲や銀河の観測成果をビジュアル中心に伝えるダミーニュースです。"),
            ("ダミーニュース{n}: 地域マーケットに限定スイーツが登場", "週末の買い物や散歩の参考になる食の話題を想定したダミーニュースです。"),
        };

        var newsCount = debugConfig.DummyNewsCount;
        var now = DateTime.Now;

        return Enumerable.Range(1, newsCount)
            .Select(index =>
            {
                var template = templates[(index - 1) % templates.Length];
                return new NewsTopicItem(
                    Title: template.Title.Replace("{n}", index.ToString()),
                    Summary: template.Summary,
                    Url: $"https://example.com/wondaywall/dummy-news-{index}",
                    PublishedAt: now.AddMinutes(-30 * index));
            })
            .ToList();
    }

    public async Task<GeneratedImageInfo> GenerateWallpaperAsync(
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        CancellationToken ct = default)
    {
        var debugConfig = configService.Current.DebugConfig;
        if (debugConfig.DummyImageDelaySeconds > 0)
            await Task.Delay(TimeSpan.FromSeconds(debugConfig.DummyImageDelaySeconds), ct);

        var (width, height) = ParseCanvasSize(context.ImageSize, context.AspectRatio);
        var path = FileNameHelper.GetImageFilePath(PathUtility.WallpaperDirectory, extension: "png");

        using var image = new Image<Rgba32>(width, height);
        for (var y = 0; y < height; y++)
        {
            ct.ThrowIfCancellationRequested();
            var t = (float)y / Math.Max(height - 1, 1);
            var r = (byte)(32 + (96 * t));
            var g = (byte)(88 + (72 * t));
            var b = (byte)(160 + (72 * (1 - t)));
            for (var x = 0; x < width; x++)
                image[x, y] = new Rgba32(r, g, b);
        }

        image.SaveAsPng(path);
        return new GeneratedImageInfo(
            FilePath: path,
            GeneratedAt: DateTime.Now,
            UsedPrompt: "[Dummy] Simulated wallpaper prompt",
            ServiceTier: serviceTier,
            SourceContext: context);
    }

    private static (int Width, int Height) ParseCanvasSize(string? imageSize, string? aspectRatio)
    {
        if (!string.IsNullOrWhiteSpace(imageSize))
        {
            var split = imageSize.Split('x');
            if (split.Length == 2
                && int.TryParse(split[0], out var width)
                && int.TryParse(split[1], out var height)
                && width > 0
                && height > 0)
            {
                return (width, height);
            }
        }

        if (!string.IsNullOrWhiteSpace(aspectRatio))
        {
            var split = aspectRatio.Split(':');
            if (split.Length == 2
                && double.TryParse(split[0], out var w)
                && double.TryParse(split[1], out var h)
                && w > 0
                && h > 0)
            {
                const int baseWidth = 1920;
                return (baseWidth, Math.Max(1, (int)Math.Round(baseWidth * h / w)));
            }
        }

        return (1920, 1080);
    }
}
