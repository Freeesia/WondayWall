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
    /// <summary>Run the full wallpaper generation and apply it.</summary>
    [Command("run-once")]
    public async Task RunOnceAsync(CancellationToken cancellationToken = default)
    {
        logger.LogInformation("Starting wallpaper generation...");
        var skipIfNoChanges = configService.Current.SkipGenerationWhenNoChanges;
        var result = await coordinator.RunAsync(skipIfNoChanges, cancellationToken);
        if (result.IsSkipped)
            logger.LogInformation("Skipped: no changes detected.");
        else if (result.IsSuccess)
        {
            logger.LogInformation("Done. Wallpaper set: {Path}", result.AppliedImagePath);
            if (!string.IsNullOrWhiteSpace(result.ErrorSummary))
                logger.LogWarning("{WarningMessage}", result.ErrorSummary);
        }
        else
            logger.LogError("Failed: {Error}", result.ErrorSummary);
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
}
