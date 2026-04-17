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
    private static readonly TimeSpan[] ScheduledSlotOffsets =
    [
        TimeSpan.Zero,
        TimeSpan.FromHours(6),
        TimeSpan.FromHours(12),
        TimeSpan.FromHours(18),
    ];

    private static readonly string HistoryFilePath = Path.Combine(
        System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
        "WondayWall", "history.json");

    public async Task<HistoryItem> RunAsync(bool skipIfNoChanges = false, CancellationToken ct = default)
    {
        if (!await Lock.WaitAsync(0, ct))
            throw new InvalidOperationException("Generation is already in progress.");

        bool isSuccess = false;
        bool isSkipped = false;
        string? errorSummary = null;
        string? appliedImagePath = null;
        List<CalendarEventItem>? usedEvents = null;
        List<NewsTopicItem>? usedTopics = null;

        try
        {
            var contextResult = await contextService.BuildContextAsync(ct);

            // スキップ条件チェック：直近の予定がなく、ニュースに変化がない場合はスキップ
            if (skipIfNoChanges
                && contextResult.CalendarEvents.Count == 0
                && !HasNewsChanged(contextResult.NewsTopics, LoadHistory()))
            {
                logger.LogInformation("変化がないため画像生成をスキップします");
                isSuccess = true;
                isSkipped = true;
            }
            else
            {
                var imageInfo = await googleAiService.GenerateWallpaperAsync(contextResult.PromptContext, ct);
                wallpaperService.SetWallpaper(imageInfo.FilePath);

                isSuccess = true;
                appliedImagePath = imageInfo.FilePath;
                usedEvents = contextResult.CalendarEvents;
                usedTopics = contextResult.NewsTopics;
            }
        }
        catch (Exception ex)
        {
            errorSummary = ex.Message;
        }

        var historyItems = LoadHistory();
        var historyItem = new HistoryItem(
            ExecutedAt: DateTimeOffset.UtcNow,
            IsSuccess: isSuccess,
            ErrorSummary: errorSummary,
            AppliedImagePath: appliedImagePath,
            UsedCalendarEvents: usedEvents,
            UsedNewsTopics: usedTopics,
            IsSkipped: isSkipped);

        try
        {
            await AppendHistoryAsync(historyItem, historyItems);
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

    public DateTimeOffset? GetPendingScheduledSlot(DateTimeOffset now)
    {
        var latestSlot = GetLatestScheduledSlotAtOrBefore(now);
        var lastCompletedRunAt = LoadHistory()
            .Where(h => h.IsSuccess)
            .Select(h => h.ExecutedAt)
            .OrderByDescending(executedAt => executedAt)
            .FirstOrDefault();

        if (lastCompletedRunAt != default && lastCompletedRunAt >= latestSlot)
            return null;

        return latestSlot;
    }

    public List<HistoryItem> LoadHistory()
    {
        return JsonFileHelper.Load<List<HistoryItem>>(HistoryFilePath) ?? [];
    }

    private async Task AppendHistoryAsync(HistoryItem item, List<HistoryItem> history)
    {
        history.Insert(0, item);

        if (history.Count > 100)
            history = history.Take(100).ToList();

        await Task.Run(() => JsonFileHelper.Save(HistoryFilePath, history));
    }

    private static DateTimeOffset GetLatestScheduledSlotAtOrBefore(DateTimeOffset now)
    {
        var localNow = now.ToLocalTime();
        var dayStart = new DateTimeOffset(localNow.Year, localNow.Month, localNow.Day, 0, 0, 0, localNow.Offset);

        for (var i = ScheduledSlotOffsets.Length - 1; i >= 0; i--)
        {
            var candidate = dayStart + ScheduledSlotOffsets[i];
            if (candidate <= localNow)
                return candidate;
        }

        return dayStart.AddDays(-1) + ScheduledSlotOffsets[^1];
    }

    /// <summary>
    /// 直前の成功した生成履歴と比較し、ニューストピックに変化があるかを返す。
    /// 前回の履歴がない場合は変化ありとみなす。
    /// </summary>
    private static bool HasNewsChanged(List<NewsTopicItem> currentNews, List<HistoryItem> history)
    {
        // スキップ判定に使う直前の成功・非スキップ履歴を取得
        var lastHistory = history
            .FirstOrDefault(h => h.IsSuccess && !h.IsSkipped);

        if (lastHistory?.UsedNewsTopics == null || lastHistory.UsedNewsTopics.Count == 0)
            return true;

        // URLがあればURLで、なければタイトルで比較（どちらもnullの場合は除外）
        var previousKeys = lastHistory.UsedNewsTopics
            .Select(n => n.Url ?? n.Title)
            .Where(k => k != null)
            .ToHashSet();

        var currentKeys = currentNews
            .Select(n => n.Url ?? n.Title)
            .Where(k => k != null)
            .ToHashSet();

        return !previousKeys.SetEquals(currentKeys);
    }
}
