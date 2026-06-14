using System.IO;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class WondayWallWidgetProvider(
    WidgetHistoryService widgetHistoryService,
    WidgetActionService widgetActionService,
    WidgetCardBuilder widgetCardBuilder,
    ILogger<WondayWallWidgetProvider> logger)
{
    private static readonly string WidgetStatePath = Path.Combine(PathUtility.AppDataDirectory, "widgets", "state.json");

    public async Task<int> RunAsync(string[] args, CancellationToken cancellationToken = default)
    {
        var size = ParseSize(GetOption(args, "--size"));
        var action = GetOption(args, "--action");
        var historyId = GetOption(args, "--history-id");
        var newsIndex = ParseInt(GetOption(args, "--news-index"));

        var state = LoadState();
        var entries = widgetHistoryService.GetDisplayItems(size);

        var currentIndex = ResolveCurrentIndex(state, entries.Count);

        if (!string.IsNullOrWhiteSpace(action))
        {
            currentIndex = await HandleActionAsync(action, historyId, newsIndex, entries, currentIndex, cancellationToken);
        }

        var entry = entries.Count == 0 ? null : entries[currentIndex];
        var payload = new
        {
            size = size.ToString().ToLowerInvariant(),
            index = currentIndex,
            total = entries.Count,
            cardJson = widgetCardBuilder.Build(size, entry, currentIndex, entries.Count),
        };

        SaveState(new WidgetProviderState(currentIndex));
        Console.WriteLine(JsonSerializer.Serialize(payload));
        return 0;
    }

    private async Task<int> HandleActionAsync(
        string action,
        string? historyId,
        int? newsIndex,
        IReadOnlyList<WidgetHistoryEntry> entries,
        int currentIndex,
        CancellationToken cancellationToken)
    {
        switch (action)
        {
            case "prev":
                if (entries.Count == 0)
                    return 0;
                return (currentIndex - 1 + entries.Count) % entries.Count;
            case "next":
                if (entries.Count == 0)
                    return 0;
                return (currentIndex + 1) % entries.Count;
            case "apply":
                if (!string.IsNullOrWhiteSpace(historyId))
                    await widgetActionService.ApplyHistoryAsync(historyId, cancellationToken);
                return currentIndex;
            case "openNews":
                if (!string.IsNullOrWhiteSpace(historyId) && newsIndex is not null)
                    widgetActionService.OpenNews(historyId, newsIndex.Value);
                return currentIndex;
            default:
                logger.LogWarning("未対応のウィジェット操作です: {Action}", action);
                return currentIndex;
        }
    }

    private static WidgetDisplaySize ParseSize(string? value)
        => value?.ToLowerInvariant() switch
        {
            "small" => WidgetDisplaySize.Small,
            "medium" => WidgetDisplaySize.Medium,
            "large" => WidgetDisplaySize.Large,
            _ => WidgetDisplaySize.Large,
        };

    private static int ResolveCurrentIndex(WidgetProviderState state, int totalCount)
    {
        if (totalCount <= 0)
            return 0;

        if (state.CurrentIndex < 0)
            return 0;

        if (state.CurrentIndex >= totalCount)
            return totalCount - 1;

        return state.CurrentIndex;
    }

    private static WidgetProviderState LoadState()
        => JsonFileHelper.Load<WidgetProviderState>(WidgetStatePath) ?? new WidgetProviderState(0);

    private static void SaveState(WidgetProviderState state)
        => JsonFileHelper.Save(WidgetStatePath, state);

    private static string? GetOption(string[] args, string optionName)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (!string.Equals(args[i], optionName, StringComparison.OrdinalIgnoreCase))
                continue;

            return args[i + 1];
        }

        return null;
    }

    private static int? ParseInt(string? value)
        => int.TryParse(value, out var intValue) ? intValue : null;

    private record WidgetProviderState(int CurrentIndex);
}
