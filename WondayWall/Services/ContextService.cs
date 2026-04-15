using System.IO;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text;
using System.ServiceModel.Syndication;
using System.Xml;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Calendar.v3;
using Google.Apis.Services;
using Google.Apis.Util.Store;
using Microsoft.Extensions.Logging;
using OpenGraphNet;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class ContextService(AppConfigService configService, IHttpClientFactory httpClientFactory, ILogger<ContextService> logger)
{
    private readonly HttpClient httpClient = httpClientFactory.CreateClient("WondayWall");
    private const string ClientId = "1032289774423-97qnlp8qkh7vca159jvq1ohggcn4qaqm.apps.googleusercontent.com";

    private static readonly byte[] _scrambledClientSecret =
        [16, 33, 39, 42, 7, 52, 122, 25, 21, 77, 7, 95, 38, 87, 23, 72, 49, 0, 13, 13, 5, 74, 31, 30, 54, 60, 23, 61, 27, 43, 4, 2, 35, 84, 52];

    private static string ClientSecret
    {
        get
        {
            var key = "WndyWl"u8;
            Span<byte> buf = stackalloc byte[_scrambledClientSecret.Length];
            for (var i = 0; i < buf.Length; i++)
                buf[i] = (byte)(_scrambledClientSecret[i] ^ key[i % key.Length]);
            return Encoding.ASCII.GetString(buf);
        }
    }

    private CalendarService? _calendarService;

    /// <summary>Googleカレンダーのイベントを非同期ストリームで返す（直近1週間先まで）</summary>
    public async IAsyncEnumerable<CalendarEventItem> FetchCalendarEventsAsync(
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var config = configService.Current;

        if (string.IsNullOrWhiteSpace(ClientId) ||
            string.IsNullOrWhiteSpace(ClientSecret))
            yield break;

        CalendarService calSvc;
        try
        {
            calSvc = await GetCalendarServiceAsync(ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "カレンダー認証に失敗しました");
            yield break;
        }

        var now = DateTime.UtcNow;
        var end = now.AddDays(7);

        var calendarIds = config.TargetCalendarIds.Count > 0
            ? config.TargetCalendarIds
            : ["primary"];

        foreach (var calId in calendarIds)
        {
            ct.ThrowIfCancellationRequested();
            Google.Apis.Calendar.v3.Data.Events result;
            try
            {
                var request = calSvc.Events.List(calId);
                request.TimeMinDateTimeOffset = now;
                request.TimeMaxDateTimeOffset = end;
                request.SingleEvents = true;
                request.OrderBy = EventsResource.ListRequest.OrderByEnum.StartTime;
                result = await request.ExecuteAsync(ct);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "カレンダーイベントの取得に失敗しました [{CalId}]", calId);
                continue;
            }

            if (result.Items == null) continue;

            foreach (var ev in result.Items)
            {
                var start = ev.Start?.DateTimeDateTimeOffset
                            ?? (ev.Start?.Date != null
                                ? DateTimeOffset.Parse(ev.Start.Date)
                                : DateTimeOffset.UtcNow);

                var endTime = ev.End?.DateTimeDateTimeOffset
                           ?? (ev.End?.Date != null
                               ? DateTimeOffset.Parse(ev.End.Date)
                               : (DateTimeOffset?)null);

                yield return new CalendarEventItem(
                    Title: ev.Summary ?? "(no title)",
                    StartTime: start,
                    EndTime: endTime,
                    Location: ev.Location,
                    Description: ev.Description);
            }
        }
    }

    /// <summary>利用可能なGoogleカレンダー一覧を非同期ストリームで返す</summary>
    public async IAsyncEnumerable<AvailableCalendar> FetchAvailableCalendarsAsync(
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(ClientId) ||
            string.IsNullOrWhiteSpace(ClientSecret))
            yield break;

        CalendarService calSvc;
        try
        {
            calSvc = await GetCalendarServiceAsync(ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "カレンダー認証に失敗しました");
            yield break;
        }

        Google.Apis.Calendar.v3.Data.CalendarList calendarList;
        try
        {
            var request = calSvc.CalendarList.List();
            calendarList = await request.ExecuteAsync(ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "カレンダー一覧の取得に失敗しました");
            yield break;
        }

        if (calendarList.Items == null) yield break;

        foreach (var c in calendarList.Items)
        {
            yield return new AvailableCalendar
            {
                Id = c.Id ?? string.Empty,
                Summary = c.Summary ?? c.Id ?? string.Empty,
            };
        }
    }

    /// <summary>
    /// RSSフィードのニューストピックをOGP情報付きで非同期ストリームで返す。
    /// 全ソースを並列でフェッチし、公開日時の新しい順（直近1週間以内）に返す。
    /// OGPは各アイテムをyieldする直前に順次取得する（不要な取得を防ぐため）。
    /// </summary>
    public async IAsyncEnumerable<NewsTopicItem> FetchNewsAsync(
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var config = configService.Current;

        if (config.RssSources.Count == 0)
            yield break;

        // 全RSSソースを並列でフェッチ（OGPなし）
        var fetchTasks = config.RssSources
            .Select(rssUrl => FetchFromRssSourceAsync(rssUrl, ct))
            .ToList();
        var allResults = await Task.WhenAll(fetchTasks);

        var weekAgo = DateTimeOffset.UtcNow.AddDays(-7);

        // 公開日時の新しい順にソート
        var sortedRawItems = allResults
            .SelectMany(items => items)
            .Where(i => i.PublishedAt >= weekAgo)
            .OrderByDescending(item => item.PublishedAt);

        // 各アイテムをyieldする直前にOGPを順次フェッチ
        foreach (var (title, summary, url, publishedAt) in sortedRawItems)
        {
            ct.ThrowIfCancellationRequested();

            string? imageUrl = null;
            string? description = null;
            if (!string.IsNullOrEmpty(url))
            {
                try
                {
                    var ogp = await OpenGraph.ParseUrlAsync(url, cancellationToken: ct);
                    if (ogp.Image != null)
                        imageUrl = ogp.Image.OriginalString;

                    // RSSにサマリーがなければOGPの説明をフォールバックとして使用
                    if (ogp.Metadata.TryGetValue("og:description", out var descMeta))
                        description = descMeta.FirstOrDefault()?.Value;
                }
                catch
                {
                    // OGP取得失敗は無視
                }
            }

            yield return new NewsTopicItem(
                Title: title,
                Summary: !string.IsNullOrEmpty(summary) ? summary : description,
                Url: url,
                PublishedAt: publishedAt,
                OgpImageUrl: imageUrl);
        }
    }

    private record RssItem(string Title, string? Summary, string? Url, DateTimeOffset PublishedAt);

    /// <summary>1つのRSSソースから7日フィルター済みの生アイテムを返す（OGPなし）</summary>
    private async Task<IReadOnlyList<RssItem>> FetchFromRssSourceAsync(string rssUrl, CancellationToken ct)
    {
        SyndicationFeed feed;
        try
        {
            var xml = await httpClient.GetStringAsync(rssUrl, ct);
            using var reader = XmlReader.Create(new StringReader(xml));
            feed = SyndicationFeed.Load(reader);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "RSSフェッチに失敗しました [{RssUrl}]", rssUrl);
            return [];
        }

        return feed.Items
            .Select(item => new RssItem(
                item.Title?.Text ?? string.Empty,
                item.Summary?.Text == "None" ? null : item.Summary?.Text,
                item.Links.FirstOrDefault()?.Uri.ToString(),
                item.PublishDate))
            .ToList();
    }

    public async Task<ContextBuildResult> BuildContextAsync(CancellationToken ct = default)
    {
        var config = configService.Current;

        // カレンダーイベントを収集
        var events = await FetchCalendarEventsAsync(ct)
            .Take(5)
            .ToListAsync(ct)
            .ConfigureAwait(false);

        // ニューストピックを収集
        var news = await FetchNewsAsync(ct)
            .Take(5)
            .ToListAsync(ct)
            .ConfigureAwait(false);

        var today = DateTimeOffset.Now.Date;
        var tomorrow = today.AddDays(1);

        // 前日イベント判定: 明日開始するイベントがあれば、そのイベントのみ対象にしてニュースを除外する
        var tomorrowEvents = events.Where(e => e.StartTime.LocalDateTime.Date == tomorrow).ToList();
        var filteredEvents = tomorrowEvents.Count > 0 ? tomorrowEvents : events;
        var filteredNews = tomorrowEvents.Count > 0 ? [] : news;

        var displayInfo = DisplayHelper.GetDisplayInfo();
        var context = new PromptContext(
            EventSummary: string.Join("\n", filteredEvents.Select(e =>
            {
                var daysUntil = (e.StartTime.LocalDateTime.Date - today).Days;
                var proximityTag = daysUntil <= 0 ? "today" : daysUntil == 1 ? "tomorrow" : $"in {daysUntil} days";
                var line = $"- {e.Title} [{proximityTag}] ({e.StartTime:yyyy/MM/dd HH:mm})" +
                           (string.IsNullOrEmpty(e.Location) ? "" : $" @ {e.Location}");
                return string.IsNullOrEmpty(e.Description)
                    ? line
                    : $"{line}\n  {e.Description}";
            })),
            NewsSummary: string.Join("\n", filteredNews.Select(n => string.IsNullOrEmpty(n.Summary) ? $"- {n.Title}" : $"- {n.Title}\n  {n.Summary}")),
            ImageSize: displayInfo.Size,
            AspectRatio: displayInfo.AspectRatio,
            AdditionalConstraints: string.IsNullOrWhiteSpace(config.UserPrompt)
                ? null
                : config.UserPrompt,
            OgpImageUrls: filteredNews.Where(n => n.OgpImageUrl != null)
                              .Select(n => n.OgpImageUrl!)
                              .Take(3)
                              .ToList());

        return new ContextBuildResult(context, filteredEvents, filteredNews);
    }

    private async Task<CalendarService> GetCalendarServiceAsync(CancellationToken ct = default)
    {
        if (_calendarService != null)
            return _calendarService;

        var credPath = Path.Combine(
            System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
            "WondayWall", "calendar-token");

        var secrets = new ClientSecrets
        {
            ClientId = ClientId,
            ClientSecret = ClientSecret,
        };

        var credential = await GoogleWebAuthorizationBroker.AuthorizeAsync(
            secrets,
            [CalendarService.Scope.CalendarReadonly],
            "user",
            ct,
            new FileDataStore(credPath, true));

        _calendarService = new CalendarService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential,
            ApplicationName = "WondayWall",
        });

        return _calendarService;
    }
}
