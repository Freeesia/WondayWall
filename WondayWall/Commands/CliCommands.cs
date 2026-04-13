using ConsoleAppFramework;
using WondayWall.Services;

namespace WondayWall.Commands;

public class CliCommands(GenerationCoordinator coordinator, ContextService contextService, GoogleAiService googleAiService)
{
    /// <summary>Run the full wallpaper generation and apply it.</summary>
    [Command("run-once")]
    public async Task RunOnceAsync(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Starting wallpaper generation...");
        var result = await coordinator.RunAsync(cancellationToken);
        Console.WriteLine(result.IsSuccess
            ? $"Done. Wallpaper set: {result.AppliedImagePath}"
            : $"Failed: {result.ErrorSummary}");
    }

    /// <summary>Check Google Calendar connection and show upcoming events.</summary>
    [Command("check-calendar")]
    public async Task CheckCalendarAsync(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Fetching calendar events...");
        await foreach (var ev in contextService.FetchCalendarEventsAsync(cancellationToken))
            Console.WriteLine($"  [{ev.StartTime:yyyy/MM/dd HH:mm}] {ev.Title}");
    }

    /// <summary>Check RSS news fetch and show matching topics.</summary>
    [Command("check-news")]
    public async Task CheckNewsAsync(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Fetching news topics...");
        await foreach (var n in contextService.FetchNewsAsync(cancellationToken))
            Console.WriteLine($"  {n.Title}");
    }

    /// <summary>Test Google AI connection by generating a sample wallpaper.</summary>
    [Command("check-google-ai")]
    public async Task CheckGoogleAiAsync(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Testing Google AI connection...");
        var info = await googleAiService.GenerateWallpaperAsync(new("Test event", "Test news", "1920x1080"), cancellationToken);
        Console.WriteLine($"Success! Image saved to: {info.FilePath}");
    }
}
