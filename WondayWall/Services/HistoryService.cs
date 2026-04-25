using System.IO;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class HistoryService
{
    private const int MaxHistoryItems = 100;

    private static readonly string HistoryFilePath =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WondayWall", "history.json");

    public List<HistoryItem> Load()
        => JsonFileHelper.Load<List<HistoryItem>>(HistoryFilePath) ?? [];

    public void Append(HistoryItem item)
    {
        var history = Load();
        JsonFileHelper.Save(
            HistoryFilePath,
            history.Prepend(item).Take(MaxHistoryItems).ToList());
    }

    public HistoryItem? GetLastSuccessfulGenerated()
        => Load()
            .Where(item => item.IsSuccess && !item.IsSkipped)
            .OrderByDescending(item => item.ExecutedAt)
            .FirstOrDefault();
}
