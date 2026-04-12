using System.IO;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GenerationCoordinator(
    ContextService contextService,
    GoogleAiService googleAiService,
    WallpaperService wallpaperService,
    ILogger<GenerationCoordinator> logger)
{
    private static readonly SemaphoreSlim Lock = new(1, 1);

    private static readonly string HistoryFilePath = Path.Combine(
        System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
        "WondayWall", "history.json");

    public async Task<HistoryItem> RunAsync(CancellationToken ct = default)
    {
        if (!await Lock.WaitAsync(0, ct))
            throw new InvalidOperationException("Generation is already in progress.");

        bool isSuccess = false;
        string? errorSummary = null;
        string? appliedImagePath = null;
        List<CalendarEventItem>? usedEvents = null;
        List<NewsTopicItem>? usedTopics = null;

        try
        {
            var contextResult = await contextService.BuildContextAsync(ct);
            var imageInfo = await googleAiService.GenerateWallpaperAsync(contextResult.PromptContext, ct);
            wallpaperService.SetWallpaper(imageInfo.FilePath);

            isSuccess = true;
            appliedImagePath = imageInfo.FilePath;
            usedEvents = contextResult.CalendarEvents;
            usedTopics = contextResult.NewsTopics;
        }
        catch (Exception ex)
        {
            errorSummary = ex.Message;
        }

        var historyItem = new HistoryItem
        {
            ExecutedAt = DateTimeOffset.UtcNow,
            IsSuccess = isSuccess,
            AppliedImagePath = appliedImagePath,
            ErrorSummary = errorSummary,
            UsedCalendarEvents = usedEvents,
            UsedNewsTopics = usedTopics,
        };

        try
        {
            await AppendHistoryAsync(historyItem);
        }
        catch (Exception ex)
        {
            // 履歴の保存失敗は生成フロー全体を止めない
            logger.LogError(ex, "履歴の保存に失敗しました");
        }
        finally
        {
            Lock.Release();
        }

        return historyItem;
    }

    public List<HistoryItem> LoadHistory()
    {
        return JsonFileHelper.Load<List<HistoryItem>>(HistoryFilePath) ?? [];
    }

    private async Task AppendHistoryAsync(HistoryItem item)
    {
        var history = LoadHistory();
        history.Insert(0, item);

        if (history.Count > 100)
            history = history.Take(100).ToList();

        await Task.Run(() => JsonFileHelper.Save(HistoryFilePath, history));
    }
}
