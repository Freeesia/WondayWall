using ConsoleAppFramework;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Services;

namespace WondayWall.Commands;

public class CliCommands(
    GenerationCoordinator coordinator,
    ContextService contextService,
    GoogleAiService googleAiService,
    AppConfigService configService,
    WidgetActionService widgetActionService,
    ILogger<CliCommands> logger)
{
    /// <summary>Run once for the current scheduled slot if it has not already been handled.</summary>
    [Command("run-once")]
    public async Task RunOnceAsync(CancellationToken cancellationToken = default)
    {
        var skipIfNoChanges = configService.Current.SkipGenerationWhenNoChanges;
        var result = await coordinator.RunScheduledAsync(skipIfNoChanges, DateTime.Now, cancellationToken);
        if (result is null)
        {
            logger.LogInformation("Skipping scheduled run: current slot is already handled.");
            return;
        }

        LogRunResult(result);
    }

    /// <summary>Generate immediately regardless of the current scheduled slot.</summary>
    [Command("generate")]
    public async Task GenerateAsync(CancellationToken cancellationToken = default)
    {
        logger.LogInformation("Starting manual wallpaper generation...");
        var result = await coordinator.RunAsync(skipIfNoChanges: false, ct: cancellationToken);
        LogRunResult(result);
    }

    /// <summary>Check Google Calendar connection and show upcoming events.</summary>
    [Command("check-calendar")]
    public async Task CheckCalendarAsync(CancellationToken cancellationToken = default)
    {
        logger.LogInformation("Fetching calendar events...");
        _ = await contextService.GetCalendarServiceInteractiveAsync(cancellationToken);
        await foreach (var ev in contextService.FetchCalendarEventsAsync(cancellationToken))
            logger.LogInformation("  [{Start:yyyy/MM/dd HH:mm}] {Title}", ev.StartTime, ev.Title);
    }

    /// <summary>Check RSS news fetch and show matching topics.</summary>
    [Command("check-news")]
    public async Task CheckNewsAsync(CancellationToken cancellationToken = default)
    {
        logger.LogInformation("Fetching news topics...");
        await foreach (var n in contextService.FetchNewsAsync(cancellationToken))
            logger.LogInformation("  {Title}", n.Title);
    }

    /// <summary>Test Google AI connection by generating a sample wallpaper.</summary>
    [Command("check-google-ai")]
    public async Task CheckGoogleAiAsync(CancellationToken cancellationToken = default)
    {
        logger.LogInformation("Testing Google AI connection...");
        var info = await googleAiService.GenerateWallpaperAsync(
            new(
                CalendarEvents:
                [
                    new PromptCalendarEvent(
                        Id: "event-1",
                        Title: "Sample trip",
                        ProximityTag: "tomorrow",
                        StartTime: DateTime.Now.AddDays(1))
                ],
                NewsTopics:
                [
                    new PromptNewsTopic(
                        Id: "news-1",
                        Title: "Sample news topic",
                        Summary: "Sample news summary")
                ],
                ImageSize: "1920x1080"),
            GoogleAiServiceTier.Standard,
            cancellationToken);
        logger.LogInformation("Success! Image saved to: {Path} ({ServiceTier})", info.FilePath, info.ServiceTier);
    }

    [Command("apply-history")]
    public async Task ApplyHistoryAsync(string id, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(id))
            throw new ArgumentException("History id must not be empty.", nameof(id));

        _ = await widgetActionService.ApplyHistoryAsync(id, cancellationToken);
    }

    [Command("open-news")]
    public Task OpenNewsAsync(string historyId, int newsIndex, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(historyId))
            throw new ArgumentException("History id must not be empty.", nameof(historyId));

        _ = widgetActionService.OpenNews(historyId, newsIndex);
        return Task.CompletedTask;
    }

#if DEBUG
    [Command("set-dummy-ai")]
    public Task SetDummyAiAsync(
        bool enabled,
        int? dummyNewsCount = null,
        int? dummyPromptDelaySeconds = null,
        int? dummyImageDelaySeconds = null,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var config = configService.Current;
        config.DebugConfig.UseDummyAiService = enabled;
        if (dummyNewsCount is not null)
            config.DebugConfig.DummyNewsCount = dummyNewsCount.Value;
        if (dummyPromptDelaySeconds is not null)
            config.DebugConfig.DummyPromptDelaySeconds = dummyPromptDelaySeconds.Value;
        if (dummyImageDelaySeconds is not null)
            config.DebugConfig.DummyImageDelaySeconds = dummyImageDelaySeconds.Value;

        config.DebugConfig.Normalize();
        configService.Save(config);

        logger.LogInformation(
            "Dummy AI service: {Enabled}, NewsCount={NewsCount}, PromptDelay={PromptDelay}s, ImageDelay={ImageDelay}s",
            config.DebugConfig.UseDummyAiService,
            config.DebugConfig.DummyNewsCount,
            config.DebugConfig.DummyPromptDelaySeconds,
            config.DebugConfig.DummyImageDelaySeconds);
        return Task.CompletedTask;
    }
#endif

    private void LogRunResult(HistoryItem result)
    {
        if (result.IsSkipped)
            logger.LogInformation("Skipped: no changes detected. ({ServiceTier})", result.ServiceTier);
        else if (result.IsSuccess)
            logger.LogInformation("Done. Wallpaper set: {Path} ({ServiceTier})", result.AppliedImagePath, result.ServiceTier);
        else
            logger.LogError("Failed: {Error}", result.ErrorSummary);
    }
}
