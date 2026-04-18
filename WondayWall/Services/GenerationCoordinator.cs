using System.IO;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GenerationCoordinator(
    ContextService contextService,
    GoogleAiService googleAiService,
    WallpaperService wallpaperService,
    AppConfigService appConfigService,
    ILogger<GenerationCoordinator> logger)
{
    private const string GenerationMutexName = @"Local\WondayWall.Generation";
    private static readonly TimeSpan GenerationMutexWaitInterval = TimeSpan.FromMilliseconds(250);
    private static readonly TimeSpan[] ScheduledSlotOffsets =
    [
        TimeSpan.Zero,
        TimeSpan.FromHours(6),
        TimeSpan.FromHours(12),
        TimeSpan.FromHours(18),
    ];

    private static readonly string HistoryFilePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WondayWall", "history.json");

    public Task<HistoryItem> RunAsync(bool skipIfNoChanges = false, CancellationToken ct = default)
        => ExecuteWithGenerationMutexAsync(() => RunCoreAsync(skipIfNoChanges, ct), ct);

    public Task<HistoryItem?> RunScheduledAsync(
        bool skipIfNoChanges = false,
        DateTimeOffset? now = null,
        CancellationToken ct = default)
    {
        var effectiveNow = now ?? DateTimeOffset.Now;
        return ExecuteWithGenerationMutexAsync(async () =>
        {
            var scheduledSlot = GetPendingScheduledSlot(effectiveNow, LoadHistory());
            if (scheduledSlot is null)
                return null;

            logger.LogInformation(
                "Starting scheduled wallpaper generation for slot {ScheduledSlot:yyyy/MM/dd HH:mm}.",
                scheduledSlot.Value.ToLocalTime());

            return await RunCoreAsync(skipIfNoChanges, ct);
        }, ct);
    }

    public List<HistoryItem> LoadHistory()
        => JsonFileHelper.Load<List<HistoryItem>>(HistoryFilePath) ?? [];

    private void AppendHistory(HistoryItem item, List<HistoryItem> history)
        => JsonFileHelper.Save(HistoryFilePath, history.Prepend(item).Take(100));

    private async Task<HistoryItem> RunCoreAsync(bool skipIfNoChanges, CancellationToken ct)
    {
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
                await wallpaperService.SetWallpaperAsync(
                    imageInfo.FilePath,
                    appConfigService.Current.UpdateLockScreen,
                    ct);

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
            AppendHistory(historyItem, historyItems);
        }
        catch (Exception ex)
        {
            // 履歴の保存失敗は生成フロー全体を止めない
            logger.LogError(ex, "履歴の保存に失敗しました");
        }

        return historyItem;
    }

    // GUI and CLI can launch generation in different processes, so guard it with an OS-wide mutex.
    private static Task<T> ExecuteWithGenerationMutexAsync<T>(Func<Task<T>> action, CancellationToken ct)
        => Task.Run(async () =>
            {
                using var mutex = new Mutex(false, GenerationMutexName);
                var hasHandle = false;

                try
                {
                    while (!hasHandle)
                    {
                        ct.ThrowIfCancellationRequested();

                        try
                        {
                            hasHandle = mutex.WaitOne(GenerationMutexWaitInterval);
                        }
                        catch (AbandonedMutexException)
                        {
                            hasHandle = true;
                        }
                    }

                    return await action();
                }
                finally
                {
                    if (hasHandle)
                        mutex.ReleaseMutex();
                }
            }, ct);

    private static DateTimeOffset? GetPendingScheduledSlot(DateTimeOffset now, List<HistoryItem> history)
    {
        var latestSlot = GetLatestScheduledSlotAtOrBefore(now);
        var lastCompletedRunAt = history
            .Where(h => h.IsSuccess)
            .Select(h => h.ExecutedAt)
            .OrderByDescending(executedAt => executedAt)
            .FirstOrDefault();

        if (lastCompletedRunAt != default && lastCompletedRunAt >= latestSlot)
            return null;

        return latestSlot;
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
