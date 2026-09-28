using System.Diagnostics;
using Microsoft.Extensions.Logging;
using WondayWall.Models;

namespace WondayWall.Services;

public class WidgetActionService(
    HistoryService historyService,
    WallpaperService wallpaperService,
    AppConfigService configService,
    ILogger<WidgetActionService> logger)
{
    public async Task<bool> ApplyHistoryAsync(string historyId, CancellationToken cancellationToken = default)
    {
        var history = historyService.GetById(historyId);
        if (history is null)
        {
            logger.LogWarning("履歴が見つかりません: {HistoryId}", historyId);
            return false;
        }

        if (!history.IsSuccess || history.IsSkipped || string.IsNullOrWhiteSpace(history.AppliedImagePath))
        {
            logger.LogWarning("壁紙再適用できない履歴です: {HistoryId}", historyId);
            return false;
        }

        await wallpaperService.SetWallpaperAsync(history.AppliedImagePath, configService.Current.UpdateLockScreen, cancellationToken);
        logger.LogInformation("履歴画像を壁紙に適用しました: {HistoryId}", historyId);
        return true;
    }

    public bool OpenNews(string historyId, int newsIndex)
    {
        var history = historyService.GetById(historyId);
        if (history?.UsedNewsTopics is null)
        {
            logger.LogWarning("ニュース情報付き履歴が見つかりません: {HistoryId}", historyId);
            return false;
        }

        if (newsIndex < 0 || newsIndex >= history.UsedNewsTopics.Count)
        {
            logger.LogWarning("ニュースインデックスが範囲外です: {HistoryId} index={NewsIndex}", historyId, newsIndex);
            return false;
        }

        var news = history.UsedNewsTopics[newsIndex];
        if (string.IsNullOrWhiteSpace(news.Url))
        {
            logger.LogWarning("URL がないニュースです: {HistoryId} index={NewsIndex}", historyId, newsIndex);
            return false;
        }

        if (!Uri.TryCreate(news.Url, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            logger.LogWarning("URL 形式が不正です: {HistoryId} index={NewsIndex}", historyId, newsIndex);
            return false;
        }

        Process.Start(new ProcessStartInfo(uri.ToString()) { UseShellExecute = true });
        logger.LogInformation("ニュースURLを開きました: {HistoryId} index={NewsIndex}", historyId, newsIndex);
        return true;
    }
}
