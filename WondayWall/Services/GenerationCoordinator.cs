using System.IO;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GenerationCoordinator(
    ContextService contextService,
    GoogleAiService googleAiService,
    WallpaperService wallpaperService)
{
    private static readonly SemaphoreSlim Lock = new(1, 1);

    private static readonly string HistoryFilePath = Path.Combine(
        System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
        "WondayWall", "history.json");

    public async Task<HistoryItem> RunAsync(CancellationToken ct = default)
    {
        if (!await Lock.WaitAsync(0, ct))
            throw new InvalidOperationException("Generation is already in progress.");

        var historyItem = new HistoryItem { ExecutedAt = DateTimeOffset.UtcNow };

        try
        {
            var context = await contextService.BuildPromptContextAsync(ct);
            var imageInfo = await googleAiService.GenerateWallpaperAsync(context, ct);
            wallpaperService.SetWallpaper(imageInfo.FilePath);

            historyItem.IsSuccess = true;
            historyItem.AppliedImagePath = imageInfo.FilePath;
        }
        catch (Exception ex)
        {
            historyItem.IsSuccess = false;
            historyItem.ErrorSummary = ex.Message;
        }
        finally
        {
            await AppendHistoryAsync(historyItem);
            Lock.Release();
        }

        return historyItem;
    }

    public List<HistoryItem> LoadHistory()
    {
        return JsonFileHelper.Load<List<HistoryItem>>(HistoryFilePath) ?? [];
    }

    private async Task AppendHistoryAsync(HistoryItem item)
    {
        var history = LoadHistory();
        history.Insert(0, item);

        if (history.Count > 100)
            history = history.Take(100).ToList();

        await Task.Run(() => JsonFileHelper.Save(HistoryFilePath, history));
    }
}
