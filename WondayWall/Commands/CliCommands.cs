using ConsoleAppFramework;
using Microsoft.Extensions.Logging;
using WondayWall.Services;

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
        var scheduledSlot = coordinator.GetPendingScheduledSlot(DateTimeOffset.Now);
        if (scheduledSlot is null)
        {
            logger.LogInformation("Skipping scheduled run: current slot is already handled.");
            return;
        }

        logger.LogInformation(
            "Starting scheduled wallpaper generation for slot {ScheduledSlot:yyyy/MM/dd HH:mm}.",
            scheduledSlot.Value.ToLocalTime());

        await RunCoreAsync(cancellationToken);
    }

    /// <summary>Generate immediately regardless of the current scheduled slot.</summary>
    [Command("generate")]
    public async Task GenerateAsync(CancellationToken cancellationToken = default)
    {
        logger.LogInformation("Starting manual wallpaper generation...");
        await RunCoreAsync(cancellationToken);
    }

    /// <summary>Check Google Calendar connection and show upcoming events.</summary>
    [Command("check-calendar")]
    public async Task CheckCalendarAsync(CancellationToken cancellationToken = default)
    {
        logger.LogInformation("Fetching calendar events...");
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
        var info = await googleAiService.GenerateWallpaperAsync(new("Test event", "Test news", "1920x1080"), cancellationToken);
        logger.LogInformation("Success! Image saved to: {Path}", info.FilePath);
    }

    private async Task RunCoreAsync(CancellationToken cancellationToken)
    {
        var skipIfNoChanges = configService.Current.SkipGenerationWhenNoChanges;
        var result = await coordinator.RunAsync(skipIfNoChanges, ct: cancellationToken);
        if (result.IsSkipped)
            logger.LogInformation("Skipped: no changes detected.");
        else if (result.IsSuccess)
            logger.LogInformation("Done. Wallpaper set: {Path}", result.AppliedImagePath);
        else
            logger.LogError("Failed: {Error}", result.ErrorSummary);
    }
}
