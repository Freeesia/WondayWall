using ConsoleAppFramework;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Services;
using WondayWall.Utils;

namespace WondayWall.Commands;

public class CliCommands(
    GenerationCoordinator coordinator,
    ContextService contextService,
    GoogleAiService googleAiService,
    AppConfigService configService,
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
            DisplayHelper.GetDisplayInfo(),
            GoogleAiServiceTier.Standard,
            cancellationToken);
        logger.LogInformation("Success! Image saved to: {Path} ({ServiceTier})", info.FilePath, info.ServiceTier);
    }

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
