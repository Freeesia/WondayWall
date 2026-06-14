using System.IO;
using Microsoft.Extensions.Logging;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.Processing;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class WidgetHistoryService(
    HistoryService historyService,
    ILogger<WidgetHistoryService> logger)
{
    private static readonly string WidgetDirectory = Path.Combine(PathUtility.AppDataDirectory, "widgets");
    private static readonly string ThumbnailDirectory = Path.Combine(WidgetDirectory, "thumbnails");

    public List<WidgetHistoryEntry> GetDisplayItems(WidgetDisplaySize size)
    {
        var history = historyService.Load();

        return history
            .Where(IsWidgetDisplayTarget)
            .OrderByDescending(item => item.ExecutedAt)
            .Select(item => TryCreateEntry(item, size))
            .OfType<WidgetHistoryEntry>()
            .ToList();
    }

    private static bool IsWidgetDisplayTarget(HistoryItem item)
        => item.IsSuccess
        && !item.IsSkipped
        && !string.IsNullOrWhiteSpace(item.AppliedImagePath)
        && File.Exists(item.AppliedImagePath)
        && item.UsedNewsTopics is { Count: > 0 };

    private WidgetHistoryEntry? TryCreateEntry(HistoryItem item, WidgetDisplaySize size)
    {
        if (item.UsedNewsTopics is null || string.IsNullOrWhiteSpace(item.AppliedImagePath))
            return null;

        var newsItems = item.UsedNewsTopics
            .Take(3)
            .Select((news, index) => new WidgetNewsEntry(index, news.Title, news.Url, news.PublishedAt))
            .ToList();

        if (newsItems.Count == 0)
            return null;

        try
        {
            var backgroundImagePath = EnsureThumbnail(item.Id, item.AppliedImagePath, size);
            return new WidgetHistoryEntry(
                HistoryId: item.Id,
                ExecutedAt: item.ExecutedAt,
                OriginalImagePath: item.AppliedImagePath,
                BackgroundImagePath: backgroundImagePath,
                NewsItems: newsItems);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ウィジェット表示用サムネイルの生成に失敗しました: {HistoryId}", item.Id);
            return null;
        }
    }

    private static string EnsureThumbnail(string historyId, string originalImagePath, WidgetDisplaySize size)
    {
        Directory.CreateDirectory(ThumbnailDirectory);

        var (width, height) = GetThumbnailSize(size);
        var thumbnailFileName = $"{historyId}_{width}x{height}.jpg";
        var thumbnailPath = Path.Combine(ThumbnailDirectory, thumbnailFileName);

        if (File.Exists(thumbnailPath)
            && File.GetLastWriteTimeUtc(thumbnailPath) >= File.GetLastWriteTimeUtc(originalImagePath))
            return thumbnailPath;

        using var image = Image.Load(originalImagePath);
        image.Mutate(ctx => ctx.Resize(new ResizeOptions
        {
            Size = new Size(width, height),
            Mode = ResizeMode.Crop,
            Position = AnchorPositionMode.Center,
        }));
        image.Save(thumbnailPath, new JpegEncoder { Quality = 90 });

        return thumbnailPath;
    }

    private static (int Width, int Height) GetThumbnailSize(WidgetDisplaySize size)
        => size switch
        {
            WidgetDisplaySize.Small => (360, 360),
            WidgetDisplaySize.Medium => (600, 360),
            WidgetDisplaySize.Large => (960, 540),
            _ => (960, 540),
        };
}
