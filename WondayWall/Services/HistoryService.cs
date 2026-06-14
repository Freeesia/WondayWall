using System.IO;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class HistoryService
{
    private const int MaxHistoryItems = 100;
    private static readonly string HistoryFilePath =
        Path.Combine(PathUtility.AppDataDirectory, "history.json");

    public List<HistoryItem> Load()
    {
        var history = JsonFileHelper.Load<List<HistoryItem>>(HistoryFilePath) ?? [];
        var normalized = NormalizeHistoryIds(history, out var hasChanged);
        if (hasChanged)
            JsonFileHelper.Save(HistoryFilePath, normalized);

        return normalized;
    }

    public void Append(HistoryItem item)
    {
        var history = Load();
        var itemWithId = string.IsNullOrWhiteSpace(item.Id)
            ? item with { Id = CreateHistoryId(item.ExecutedAt) }
            : item;
        JsonFileHelper.Save(
            HistoryFilePath,
            history.Prepend(itemWithId).Take(MaxHistoryItems).ToList());
    }

    public HistoryItem? GetLastSuccessfulGenerated()
        => Load()
            .Where(item => item.IsSuccess && !item.IsSkipped)
            .OrderByDescending(item => item.ExecutedAt)
            .FirstOrDefault();

    public HistoryItem? GetById(string id)
        => Load().FirstOrDefault(item => item.Id == id);

    private static List<HistoryItem> NormalizeHistoryIds(List<HistoryItem> history, out bool hasChanged)
    {
        hasChanged = false;
        var normalized = new List<HistoryItem>(history.Count);
        foreach (var item in history)
        {
            if (!string.IsNullOrWhiteSpace(item.Id))
            {
                normalized.Add(item);
                continue;
            }

            hasChanged = true;
            normalized.Add(item with { Id = CreateHistoryId(item.ExecutedAt) });
        }

        return normalized;
    }

    private static string CreateHistoryId(DateTime executedAt)
        => $"{executedAt:yyyyMMddHHmmssfff}-{Guid.NewGuid():N}";
}
