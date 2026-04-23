using System.IO;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GenerationCoordinator(
    AppConfigService configService,
    ContextService contextService,
    GoogleAiService googleAiService,
    WallpaperService wallpaperService,
    ILogger<GenerationCoordinator> logger)
{
    private const string GenerationMutexName = @"Local\WondayWall.Generation";
    private static readonly TimeSpan GenerationMutexWaitInterval = TimeSpan.FromMilliseconds(250);
    private static readonly string HistoryFilePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WondayWall", "history.json");

    public Task<HistoryItem> RunAsync(bool skipIfNoChanges = false, CancellationToken ct = default)
        => ExecuteWithGenerationMutexAsync(() => RunCoreAsync(skipIfNoChanges, ct), ct);

    public Task<HistoryItem?> RunScheduledAsync(
        bool skipIfNoChanges = false,
        DateTime? now = null,
        CancellationToken ct = default)
    {
        var effectiveNow = now ?? DateTime.Now;
        var runsPerDay = ScheduleHelper.NormalizeRunsPerDay(configService.Current.RunsPerDay);

        return ExecuteWithGenerationMutexAsync(async () =>
        {
            var scheduledSlot = GetPendingScheduledSlot(effectiveNow, LoadHistory(), runsPerDay);
            if (scheduledSlot is null)
                return null;

            logger.LogInformation(
                "{RunsPerDay}回/日スケジュールの枠 {ScheduledSlot:yyyy/MM/dd HH:mm} の壁紙生成を開始します。",
                runsPerDay,
                scheduledSlot.Value);

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
        var historyItems = LoadHistory();

        try
        {
            var contextResult = await contextService.BuildContextAsync(ct);
            var promptContext = contextResult.PromptContext;

            // UseCurrentWallpaperAsBase が有効なら直前の成功生成画像をベースとして設定
            if (configService.Current.UseCurrentWallpaperAsBase)
            {
                var lastSuccessHistory = historyItems
                    .OrderByDescending(h => h.ExecutedAt)
                    .FirstOrDefault(h => h.IsSuccess
                                        && !h.IsSkipped
                                        && h.AppliedImagePath != null
                                        && File.Exists(h.AppliedImagePath));
                if (lastSuccessHistory?.AppliedImagePath != null)
                {
                    promptContext = promptContext with
                    {
                        BaseImagePath = lastSuccessHistory.AppliedImagePath,
                        // 削除された要素を判定するために前回の生成コンテキストを渡す
                        PreviousCalendarEvents = lastSuccessHistory.UsedCalendarEvents,
                        PreviousNewsTopics = lastSuccessHistory.UsedNewsTopics,
                    };
                }
            }

            // スキップ条件チェック：直近の予定がなく、ニュースに変化がない場合はスキップ
            if (skipIfNoChanges
                && contextResult.CalendarEvents.Count == 0
                && !HasNewsChanged(contextResult.NewsTopics, historyItems))
            {
                logger.LogInformation("変化がないため画像生成をスキップします");
                isSuccess = true;
                isSkipped = true;
            }
            else
            {
                var imageInfo = await googleAiService.GenerateWallpaperAsync(promptContext, ct);
                await wallpaperService.SetWallpaperAsync(
                    imageInfo.FilePath,
                    configService.Current.UpdateLockScreen,
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

        var historyItem = new HistoryItem(
            ExecutedAt: DateTime.Now,
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

    // GUI と CLI が別プロセスで同時起動し得るため、OS 全体で共有する Mutex で直列化する。
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

    private static DateTime? GetPendingScheduledSlot(DateTime now, List<HistoryItem> history, int runsPerDay)
    {
        var latestSlot = ScheduleHelper.GetLatestScheduledSlotAtOrBefore(now, runsPerDay);
        var lastCompletedRunAt = history
            .Where(h => h.IsSuccess)
            .Select(h => h.ExecutedAt)
            .OrderByDescending(executedAt => executedAt)
            .FirstOrDefault();

        if (lastCompletedRunAt != default && lastCompletedRunAt >= latestSlot)
            return null;

        return latestSlot;
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
