using System.IO;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class DummyAiService(AppConfigService configService) : IAiService
{
    public List<NewsTopicItem> BuildNewsTopics()
    {
        var debugConfig = configService.Current.DebugConfig;
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
                    PublishedAt: now.AddHours(-index));
            })
            .ToList();
    }

    public async Task<PromptGenerationResult> GeneratePromptAsync(
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        CancellationToken cancellationToken = default)
    {
        var debugConfig = configService.Current.DebugConfig;
        if (debugConfig.DummyPromptDelaySeconds > 0)
            await Task.Delay(TimeSpan.FromSeconds(debugConfig.DummyPromptDelaySeconds), cancellationToken);

        var news = BuildNewsTopics();
        var selectedIds = (context.NewsTopics ?? [])
            .Take(news.Count)
            .Select(topic => topic.Id)
            .ToList();

        return new PromptGenerationResult(
            ImagePrompt: "[Dummy] Simulated Windows wallpaper prompt",
            SelectedNewsTopics: news,
            SelectedNewsIds: selectedIds,
            ServiceTier: serviceTier);
    }

    public Task<PromptContext> FetchOgpImagesAsync(
        PromptContext context,
        IReadOnlyList<string> selectedNewsIds,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(context);
    }

    public async Task<GeneratedImageInfo> GenerateImageFromPromptAsync(
        string imagePrompt,
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        CancellationToken cancellationToken = default)
    {
        var debugConfig = configService.Current.DebugConfig;
        if (debugConfig.DummyImageDelaySeconds > 0)
            await Task.Delay(TimeSpan.FromSeconds(debugConfig.DummyImageDelaySeconds), cancellationToken);

        var (width, height) = ParseCanvasSize(context.ImageSize, context.AspectRatio);
        var path = FileNameHelper.GetImageFilePath(PathUtility.WallpaperDirectory, extension: "png");

        using var image = new Image<Rgba32>(width, height);
        var random = new Random();
        var gradientA = ColorFromHsv(random.Next(0, 360), random.NextSingle() * 0.4f + 0.45f, random.NextSingle() * 0.5f + 0.45f);
        var gradientB = ColorFromHsv(random.Next(0, 360), random.NextSingle() * 0.4f + 0.45f, random.NextSingle() * 0.5f + 0.45f);
        var gradientC = ColorFromHsv(random.Next(0, 360), random.NextSingle() * 0.4f + 0.45f, random.NextSingle() * 0.5f + 0.45f);

        for (var y = 0; y < height; y++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var t = (float)y / Math.Max(height - 1, 1f);
            var blend = t < 0.55f ? t / 0.55f : (t - 0.55f) / 0.45f;
            var from = t < 0.55f ? gradientA : gradientB;
            var to = t < 0.55f ? gradientB : gradientC;
            for (var x = 0; x < width; x++)
            {
                var noise = (random.NextSingle() - 0.5f) * 0.04f;
                image[x, y] = Lerp(from, to, Math.Clamp(blend + noise, 0f, 1f));
            }
        }

        for (var i = 0; i < 10; i++)
        {
            var alpha = (byte)random.Next(48, 132);
            var color = new Rgba32(
                (byte)random.Next(0, 255),
                (byte)random.Next(0, 255),
                (byte)random.Next(0, 255),
                alpha);
            var centerX = random.Next(0, width);
            var centerY = random.Next(0, height);
            var radius = random.Next(Math.Max(width / 10, 1), Math.Max(width / 3, 2));
            PaintCircle(image, centerX, centerY, radius, color);
        }

        image.SaveAsPng(path);
        return new GeneratedImageInfo(
            FilePath: path,
            GeneratedAt: DateTime.Now,
            UsedPrompt: imagePrompt,
            ServiceTier: serviceTier,
            SourceContext: context);
    }

    private static (int Width, int Height) ParseCanvasSize(string? imageSize, string? aspectRatio)
    {
        var longEdge = imageSize?.ToUpperInvariant() switch
        {
            "4K" => 2048,
            "2K" => 1440,
            "1K" => 1024,
            "512" => 512,
            _ => 1024,
        };

        var ratio = ParseAspectRatio(aspectRatio);
        if (ratio <= 1.0)
        {
            return (
                Math.Max(256, (int)Math.Round(longEdge * ratio)),
                longEdge);
        }

        return (
            longEdge,
            Math.Max(256, (int)Math.Round(longEdge / ratio)));
    }

    private static double ParseAspectRatio(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return 9.0 / 16.0;

        var split = value.Split(':');
        if (split.Length != 2
            || !double.TryParse(split[0], out var width)
            || !double.TryParse(split[1], out var height)
            || width <= 0
            || height <= 0)
        {
            return 9.0 / 16.0;
        }

        return width / height;
    }

    private static Rgba32 Lerp(Rgba32 from, Rgba32 to, float t)
    {
        return new Rgba32(
            (byte)Math.Round(from.R + (to.R - from.R) * t),
            (byte)Math.Round(from.G + (to.G - from.G) * t),
            (byte)Math.Round(from.B + (to.B - from.B) * t),
            (byte)Math.Round(from.A + (to.A - from.A) * t));
    }

    private static Rgba32 ColorFromHsv(int hue, float saturation, float value)
    {
        var h = ((hue % 360) + 360) % 360;
        var s = Math.Clamp(saturation, 0f, 1f);
        var v = Math.Clamp(value, 0f, 1f);

        var c = v * s;
        var x = c * (1f - Math.Abs(((h / 60f) % 2f) - 1f));
        var m = v - c;

        var (r1, g1, b1) = h switch
        {
            < 60 => (c, x, 0f),
            < 120 => (x, c, 0f),
            < 180 => (0f, c, x),
            < 240 => (0f, x, c),
            < 300 => (x, 0f, c),
            _ => (c, 0f, x),
        };

        return new Rgba32(
            (byte)Math.Round((r1 + m) * 255f),
            (byte)Math.Round((g1 + m) * 255f),
            (byte)Math.Round((b1 + m) * 255f),
            255);
    }

    private static void PaintCircle(Image<Rgba32> image, int centerX, int centerY, int radius, Rgba32 color)
    {
        var radiusSquared = radius * radius;
        var minX = Math.Max(centerX - radius, 0);
        var maxX = Math.Min(centerX + radius, image.Width - 1);
        var minY = Math.Max(centerY - radius, 0);
        var maxY = Math.Min(centerY + radius, image.Height - 1);

        for (var y = minY; y <= maxY; y++)
        {
            var dy = y - centerY;
            for (var x = minX; x <= maxX; x++)
            {
                var dx = x - centerX;
                if (dx * dx + dy * dy > radiusSquared)
                    continue;

                var baseColor = image[x, y];
                image[x, y] = AlphaBlend(baseColor, color);
            }
        }
    }

    private static Rgba32 AlphaBlend(Rgba32 background, Rgba32 foreground)
    {
        var alpha = foreground.A / 255f;
        var inv = 1f - alpha;
        return new Rgba32(
            (byte)Math.Round((foreground.R * alpha) + (background.R * inv)),
            (byte)Math.Round((foreground.G * alpha) + (background.G * inv)),
            (byte)Math.Round((foreground.B * alpha) + (background.B * inv)),
            255);
    }
}
