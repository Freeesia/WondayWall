using ConsoleAppFramework;
using WondayWall.Models;
using WondayWall.Services;

namespace WondayWall.Commands;

public class CliCommands(
    GenerationCoordinator coordinator,
    ContextService contextService,
    GoogleAiService googleAiService)
{
    /// <summary>Run the full wallpaper generation and apply it.</summary>
    [Command("run-once")]
    public async Task RunOnceAsync(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Starting wallpaper generation...");
        try
        {
            var result = await coordinator.RunAsync(cancellationToken);
            Console.WriteLine(result.IsSuccess
                ? $"Done. Wallpaper set: {result.AppliedImagePath}"
                : $"Failed: {result.ErrorSummary}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: {ex.Message}");
            Environment.Exit(1);
        }
    }

    /// <summary>Generate a wallpaper (alias for run-once).</summary>
    [Command("generate")]
    public async Task GenerateAsync(CancellationToken cancellationToken = default)
    {
        await RunOnceAsync(cancellationToken);
    }

    /// <summary>Check Google Calendar connection and show upcoming events.</summary>
    [Command("check-calendar")]
    public async Task CheckCalendarAsync(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Fetching calendar events...");
        try
        {
            var events = new List<CalendarEventItem>();
            await foreach (var ev in contextService.FetchCalendarEventsAsync(cancellationToken))
                events.Add(ev);

            if (events.Count == 0)
            {
                Console.WriteLine("No events found (or calendar not configured).");
                return;
            }

            Console.WriteLine($"Found {events.Count} event(s):");
            foreach (var ev in events)
                Console.WriteLine($"  [{ev.StartTime:yyyy/MM/dd HH:mm}] {ev.Title}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Calendar check failed: {ex.Message}");
            Environment.Exit(1);
        }
    }

    /// <summary>Check RSS news fetch and show matching topics.</summary>
    [Command("check-news")]
    public async Task CheckNewsAsync(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Fetching news topics...");
        try
        {
            var news = new List<NewsTopicItem>();
            await foreach (var n in contextService.FetchNewsAsync(cancellationToken))
                news.Add(n);

            if (news.Count == 0)
            {
                Console.WriteLine("No news topics found (or RSS sources not configured).");
                return;
            }

            Console.WriteLine($"Found {news.Count} topic(s):");
            foreach (var n in news)
                Console.WriteLine($"  {n.Title}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"News check failed: {ex.Message}");
            Environment.Exit(1);
        }
    }

    /// <summary>Test Google AI connection by generating a sample wallpaper.</summary>
    [Command("check-google-ai")]
    public async Task CheckGoogleAiAsync(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Testing Google AI connection...");
        try
        {
            var context = new PromptContext
            {
                EventSummary = "Test event",
                NewsSummary = "Test news",
                ImageSize = "1920x1080",
            };

            var info = await googleAiService.GenerateWallpaperAsync(context, cancellationToken);
            Console.WriteLine($"Success! Image saved to: {info.FilePath}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Google AI check failed: {ex.Message}");
            Environment.Exit(1);
        }
    }
}
