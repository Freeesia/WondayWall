using System.IO;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.ServiceModel.Syndication;
using System.Xml;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Auth.OAuth2.Flows;
using Google.Apis.Auth.OAuth2.Responses;
using Google.Apis.Calendar.v3;
using Google.Apis.Services;
using Google.Apis.Util.Store;
using Microsoft.Extensions.Logging;
using OpenGraphNet;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class ContextService(
    AppConfigService configService,
    HistoryService historyService,
    IHttpClientFactory httpClientFactory,
    ILogger<ContextService> logger)
{
    private const int MaxPromptNewsCount = 10;
    private const int MaxRecentNewsCountSinceLastGeneration = 3;
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

    /// <summary>
    /// ブラウザ認証を表示せずにGoogleカレンダーへアクセス可能かを確認する。
    /// </summary>
    public async Task<bool> CanAccessCalendarSilentlyAsync(CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(ClientId) ||
            string.IsNullOrWhiteSpace(ClientSecret))
            return false;

        var dataStore = CreateCalendarTokenStore();
        var existingToken = await dataStore.GetAsync<TokenResponse>("user");
        if (existingToken == null)
            return false;

        try
        {
            _ = await GetCalendarServiceAsync(dataStore, existingToken, ct);
            return true;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "サイレントなカレンダー接続確認に失敗しました");
            return false;
        }
    }

    /// <summary>Googleカレンダーのイベントを非同期ストリームで返す（直近1週間先まで）</summary>
    public async IAsyncEnumerable<CalendarEventItem> FetchCalendarEventsAsync(
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

        var now = DateTime.UtcNow;
        var end = now.AddDays(7);

        const string calendarId = "primary";

        ct.ThrowIfCancellationRequested();
        Google.Apis.Calendar.v3.Data.Events result;
        try
        {
            var request = calSvc.Events.List(calendarId);
            request.TimeMinDateTimeOffset = now;
            request.TimeMaxDateTimeOffset = end;
            request.SingleEvents = true;
            request.OrderBy = EventsResource.ListRequest.OrderByEnum.StartTime;
            result = await request.ExecuteAsync(ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "プライマリカレンダーのイベント取得に失敗しました");
            yield break;
        }

        if (result.Items == null)
            yield break;

        foreach (var ev in result.Items)
        {
            var start = ev.Start?.DateTimeDateTimeOffset is { } startDateTimeOffset
                ? startDateTimeOffset.LocalDateTime
                : ev.Start?.Date != null
                    ? DateTime.Parse(ev.Start.Date, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal)
                    : DateTime.Now;

            var endTime = ev.End?.DateTimeDateTimeOffset is { } endDateTimeOffset
                ? endDateTimeOffset.LocalDateTime
                : ev.End?.Date != null
                    ? DateTime.Parse(ev.End.Date, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal)
                    : (DateTime?)null;

            yield return new CalendarEventItem(
                Title: ev.Summary ?? "(no title)",
                StartTime: start,
                EndTime: endTime,
                Location: ev.Location,
                Description: ev.Description);
        }
    }

    /// <summary>
    /// RSSフィードのニューストピックを非同期ストリームで返す。
    /// UI表示と接続確認用途のため、直近1週間の取得結果一覧をそのまま返す。
    /// </summary>
    public async IAsyncEnumerable<NewsTopicItem> FetchNewsAsync(
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var recentNews = await FetchRecentRssItemsAsync(configService.Current.RssSources, ct);
        foreach (var item in recentNews)
        {
            ct.ThrowIfCancellationRequested();
            yield return item.ToNewsTopicItem();
        }
    }

    private record RssItem(
        string SourceRssUrl,
        string Title,
        string? Summary,
        string? Url,
        DateTime PublishedAt,
        string? DuplicateKey,
        string StableId)
    {
        public NewsTopicItem ToNewsTopicItem(string? summaryOverride = null, string? ogpImageUrl = null)
            => new(
                Title,
                summaryOverride ?? Summary,
                Url,
                PublishedAt,
                ogpImageUrl);
    }

    private async Task<List<RssItem>> FetchRecentRssItemsAsync(IReadOnlyList<string> rssSources, CancellationToken ct)
    {
        if (rssSources.Count == 0)
            return [];

        var weekAgo = DateTime.Now.AddDays(-7);
        var fetchTasks = rssSources
            .Select(rssUrl => FetchFromRssSourceAsync(rssUrl, weekAgo, ct))
            .ToList();
        var allResults = await Task.WhenAll(fetchTasks);

        return allResults
            .SelectMany(items => items)
            .OrderByDescending(item => item.PublishedAt)
            .ToList();
    }

    /// <summary>1つのRSSソースから7日フィルター済みの生アイテムを返す（OGPなし）</summary>
    private async Task<IReadOnlyList<RssItem>> FetchFromRssSourceAsync(string rssUrl, DateTime weekAgo, CancellationToken ct)
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
                SourceRssUrl: rssUrl,
                Title: item.Title?.Text ?? string.Empty,
                Summary: item.Summary?.Text == "None" ? null : item.Summary?.Text,
                Url: item.Links.FirstOrDefault()?.Uri.ToString(),
                PublishedAt: item.PublishDate.LocalDateTime,
                DuplicateKey: CreateDuplicateKey(item.Links.FirstOrDefault()?.Uri.ToString(), item.Title?.Text),
                StableId: CreateStableId(
                    rssUrl,
                    item.Id,
                    item.Links.FirstOrDefault()?.Uri.ToString(),
                    item.PublishDate.LocalDateTime,
                    item.Title?.Text)))
            .Where(item => item.PublishedAt >= weekAgo)
            .OrderByDescending(item => item.PublishedAt)
            .ToList();
    }

    public async Task<ContextBuildResult> BuildContextAsync(CancellationToken ct = default)
    {
        var config = configService.Current;

        // カレンダーイベントを収集
        var events = await FetchCalendarEventsAsync(ct: ct)
            .Take(5)
            .ToListAsync(ct)
            .ConfigureAwait(false);

        // ニューストピックを収集
        var news = await BuildPromptNewsAsync(ct).ConfigureAwait(false);

        var today = DateTime.Today;

        var displayInfo = DisplayHelper.GetDisplayInfo();
        var context = new PromptContext(
            CalendarEvents: events.Select((eventItem, index) => new PromptCalendarEvent(
                Id: $"event-{index + 1}",
                Title: eventItem.Title,
                ProximityTag: GetProximityTag(eventItem.StartTime, today),
                StartTime: eventItem.StartTime,
                EndTime: eventItem.EndTime,
                Location: eventItem.Location,
                Description: eventItem.Description))
                .ToList(),
            NewsTopics: news.Select((newsItem, index) => new PromptNewsTopic(
                Id: $"news-{index + 1}",
                Title: newsItem.Title,
                Summary: newsItem.Summary,
                Url: newsItem.Url,
                PublishedAt: newsItem.PublishedAt,
                OgpImageUrl: newsItem.OgpImageUrl))
                .ToList(),
            ImageSize: displayInfo.Size,
            AspectRatio: displayInfo.AspectRatio,
            AdditionalConstraints: string.IsNullOrWhiteSpace(config.UserPrompt)
                ? null
                : config.UserPrompt);

        return new ContextBuildResult(context, events, news);
    }

    private async Task<List<NewsTopicItem>> BuildPromptNewsAsync(CancellationToken ct)
    {
        var recentNews = await FetchRecentRssItemsAsync(configService.Current.RssSources, ct);
        var lastGeneratedAt = historyService.GetLastSuccessfulGenerated()?.ExecutedAt;
        var selectedNews = SelectPromptNewsItems(recentNews, lastGeneratedAt);
        return await EnrichWithOgpAsync(selectedNews, ct);
    }

    private async Task<List<NewsTopicItem>> EnrichWithOgpAsync(IReadOnlyList<RssItem> selectedNews, CancellationToken ct)
    {
        var enrichedNews = new List<NewsTopicItem>(selectedNews.Count);

        foreach (var item in selectedNews.OrderByDescending(item => item.PublishedAt))
        {
            ct.ThrowIfCancellationRequested();

            string? summary = item.Summary;
            string? ogpImageUrl = null;

            if (!string.IsNullOrWhiteSpace(item.Url))
            {
                try
                {
                    var ogp = await OpenGraph.ParseUrlAsync(item.Url, cancellationToken: ct);
                    if (ogp.Image != null)
                        ogpImageUrl = ogp.Image.OriginalString;

                    if (string.IsNullOrWhiteSpace(summary)
                        && ogp.Metadata.TryGetValue("og:description", out var descriptionMetadata))
                    {
                        summary = descriptionMetadata.FirstOrDefault()?.Value;
                    }
                }
                catch
                {
                    // OGP取得失敗は無視
                }
            }

            enrichedNews.Add(item.ToNewsTopicItem(summary, ogpImageUrl));
        }

        return enrichedNews;
    }

    private static List<RssItem> SelectPromptNewsItems(IReadOnlyList<RssItem> recentNews, DateTime? lastGeneratedAt)
    {
        if (recentNews.Count == 0)
            return [];

        var selectedNews = new List<RssItem>(MaxPromptNewsCount);
        var selectedKeys = new HashSet<string>(StringComparer.Ordinal);

        if (lastGeneratedAt is DateTime lastGenerated)
        {
            var recentSinceLastGeneration = recentNews
                .Where(item => item.PublishedAt > lastGenerated)
                .OrderBy(item => ComputeStableSelectionOrder(item, lastGenerated))
                .ThenByDescending(item => item.PublishedAt)
                .Take(MaxRecentNewsCountSinceLastGeneration)
                .ToList();

            AddSelectedNews(selectedNews, selectedKeys, recentSinceLastGeneration);
        }

        var representativeNews = recentNews
            .GroupBy(item => item.SourceRssUrl)
            .Select(group => group.FirstOrDefault(item => !selectedKeys.Contains(GetSelectionKey(item))))
            .Where(item => item is not null)
            .Select(item => item!)
            .OrderByDescending(item => item.PublishedAt)
            .ToList();

        AddSelectedNews(selectedNews, selectedKeys, representativeNews);

        var remainingNews = recentNews
            .Where(item => !selectedKeys.Contains(GetSelectionKey(item)))
            .OrderByDescending(item => item.PublishedAt);

        AddSelectedNews(selectedNews, selectedKeys, remainingNews);

        return selectedNews
            .OrderByDescending(item => item.PublishedAt)
            .ToList();
    }

    private static void AddSelectedNews(
        List<RssItem> selectedNews,
        HashSet<string> selectedKeys,
        IEnumerable<RssItem> candidates)
    {
        foreach (var item in candidates)
        {
            if (selectedNews.Count >= MaxPromptNewsCount)
                break;

            var selectionKey = GetSelectionKey(item);
            if (!selectedKeys.Add(selectionKey))
                continue;

            selectedNews.Add(item);
        }
    }

    private static string GetSelectionKey(RssItem item)
        => item.DuplicateKey ?? item.StableId;

    /// <summary>
    /// 同じ候補集合なら同じ3件になるように疑似乱択する。
    /// スキップ判定がランダム差分で揺れないようにするため。
    /// </summary>
    private static string ComputeStableSelectionOrder(RssItem item, DateTime lastGeneratedAt)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes($"{lastGeneratedAt:O}|{GetSelectionKey(item)}"));
        return Convert.ToHexString(bytes);
    }

    private static string? CreateDuplicateKey(string? url, string? title)
    {
        if (!string.IsNullOrWhiteSpace(url))
            return url.Trim();

        if (!string.IsNullOrWhiteSpace(title))
            return title.Trim();

        return null;
    }

    private static string CreateStableId(string rssUrl, string? itemId, string? url, DateTime publishedAt, string? title)
        => string.Join(
            "|",
            rssUrl.Trim(),
            itemId?.Trim() ?? string.Empty,
            url?.Trim() ?? string.Empty,
            publishedAt.ToString("O", CultureInfo.InvariantCulture),
            title?.Trim() ?? string.Empty);

    private static string GetProximityTag(DateTime startTime, DateTime today)
    {
        var daysUntil = (startTime.Date - today).Days;
        return daysUntil <= 0 ? "today" : daysUntil == 1 ? "tomorrow" : $"in {daysUntil} days";
    }

    private async Task<CalendarService> GetCalendarServiceAsync(CancellationToken ct = default)
    {
        if (_calendarService != null)
            return _calendarService;

        var dataStore = CreateCalendarTokenStore();
        var existingToken = await dataStore.GetAsync<TokenResponse>("user");
        if (existingToken == null)
            throw new InvalidOperationException("Googleカレンダーは未接続です。接続ボタンから認証してください。");

        return await GetCalendarServiceAsync(dataStore, existingToken, ct);
    }

    private async Task<CalendarService> GetCalendarServiceAsync(
        FileDataStore dataStore,
        TokenResponse existingToken,
        CancellationToken ct = default)
    {
        if (_calendarService != null)
            return _calendarService;

        var secrets = new ClientSecrets
        {
            ClientId = ClientId,
            ClientSecret = ClientSecret,
        };

        var flow = new GoogleAuthorizationCodeFlow(new GoogleAuthorizationCodeFlow.Initializer
        {
            ClientSecrets = secrets,
            Scopes = [CalendarService.Scope.CalendarReadonly],
            DataStore = dataStore,
        });
        var credential = new UserCredential(flow, "user", existingToken);

        if (IsTokenExpired(existingToken, DateTime.UtcNow))
        {
            var refreshed = await credential.RefreshTokenAsync(ct);
            if (!refreshed)
                throw new InvalidOperationException("Googleカレンダーの認証トークンが期限切れです。接続ボタンから再認証してください。");
        }

        _calendarService = new CalendarService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential,
            ApplicationName = "WondayWall",
        });

        return _calendarService;
    }

    private static bool IsTokenExpired(TokenResponse token, DateTime utcNow)
    {
        if (token.ExpiresInSeconds is not long expiresInSeconds ||
            expiresInSeconds <= 0 ||
            token.IssuedUtc == default)
            return true;

        var expiresAtUtc = token.IssuedUtc.AddSeconds(expiresInSeconds);
        return utcNow >= expiresAtUtc.AddMinutes(-1);
    }

    public async Task<CalendarService> GetCalendarServiceInteractiveAsync(CancellationToken ct = default)
    {
        if (_calendarService != null)
            return _calendarService;

        var secrets = new ClientSecrets
        {
            ClientId = ClientId,
            ClientSecret = ClientSecret,
        };
        var dataStore = CreateCalendarTokenStore();
        var credential = await GoogleWebAuthorizationBroker.AuthorizeAsync(
            secrets,
            [CalendarService.Scope.CalendarReadonly],
            "user",
            ct,
            dataStore);

        _calendarService = new CalendarService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential,
            ApplicationName = "WondayWall",
        });

        return _calendarService;
    }

    private static FileDataStore CreateCalendarTokenStore()
    {
        var credPath = Path.Combine(
            System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
            "WondayWall", "calendar-token");
        return new FileDataStore(credPath, true);
    }
}
