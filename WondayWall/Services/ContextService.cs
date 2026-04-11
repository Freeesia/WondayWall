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
using OpenGraphNet;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class ContextService(AppConfigService configService)
{
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

    private static readonly HttpClient SharedHttpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(30),
    };

    private CalendarService? _calendarService;

    /// <summary>Googleカレンダーのイベントを非同期ストリームで返す</summary>
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
            Console.Error.WriteLine($"Calendar auth error: {ex.Message}");
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
                Console.Error.WriteLine($"Calendar fetch error [{calId}]: {ex.Message}");
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

                yield return new CalendarEventItem
                {
                    Title = ev.Summary ?? "(no title)",
                    StartTime = start,
                    EndTime = endTime,
                    Location = ev.Location,
                    Description = ev.Description,
                };
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
            Console.Error.WriteLine($"Calendar auth error: {ex.Message}");
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
            Console.Error.WriteLine($"Calendar list fetch error: {ex.Message}");
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

    /// <summary>RSSフィードのニューストピックをOGP情報付きで非同期ストリームで返す</summary>
    public async IAsyncEnumerable<NewsTopicItem> FetchNewsAsync(
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var config = configService.Current;

        if (config.RssSources.Count == 0)
            yield break;

        foreach (var rssUrl in config.RssSources)
        {
            ct.ThrowIfCancellationRequested();

            // ファビコンURLをRSSホストから生成
            string? faviconUrl = null;
            if (Uri.TryCreate(rssUrl, UriKind.Absolute, out var rssUri))
                faviconUrl = $"https://www.google.com/s2/favicons?sz=32&domain={rssUri.Host}";

            SyndicationFeed feed;
            try
            {
                var xml = await SharedHttpClient.GetStringAsync(rssUrl, ct);
                using var reader = XmlReader.Create(new StringReader(xml));
                feed = SyndicationFeed.Load(reader);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"RSS fetch error [{rssUrl}]: {ex.Message}");
                continue;
            }

            foreach (var item in feed.Items)
            {
                ct.ThrowIfCancellationRequested();

                var title = item.Title?.Text ?? string.Empty;
                var summary = item.Summary?.Text;
                var url = item.Links.FirstOrDefault()?.Uri.ToString();

                var matched = config.InterestKeywords
                    .Where(k => title.Contains(k, StringComparison.OrdinalIgnoreCase)
                             || (summary?.Contains(k, StringComparison.OrdinalIgnoreCase) ?? false))
                    .ToList();

                if (config.InterestKeywords.Count > 0 && matched.Count == 0)
                    continue;

                // OGP画像URLを取得
                string? ogpImageUrl = null;
                if (!string.IsNullOrEmpty(url))
                {
                    try
                    {
                        var ogp = await OpenGraph.ParseUrlAsync(url, cancellationToken: ct);
                        if (ogp.Image != null)
                            ogpImageUrl = ogp.Image.OriginalString;
                    }
                    catch
                    {
                        // OGP取得失敗は無視
                    }
                }

                yield return new NewsTopicItem
                {
                    Title = title,
                    Summary = summary,
                    Url = url,
                    FetchedAt = DateTimeOffset.UtcNow,
                    MatchedKeywords = matched,
                    PublishedAt = item.PublishDate.Year > 1990 ? item.PublishDate : null,
                    OgpImageUrl = ogpImageUrl,
                    FaviconUrl = faviconUrl,
                };
            }
        }
    }

    public async Task<ContextBuildResult> BuildContextAsync(CancellationToken ct = default)
    {
        var config = configService.Current;

        // カレンダーイベントを収集
        var events = new List<CalendarEventItem>();
        await foreach (var ev in FetchCalendarEventsAsync(ct))
            events.Add(ev);

        // ニューストピックを収集
        var news = new List<NewsTopicItem>();
        await foreach (var n in FetchNewsAsync(ct))
            news.Add(n);

        var eventSummary = events.Count == 0
            ? "No upcoming calendar events."
            : string.Join("\n", events.Take(5).Select(e =>
                $"- {e.Title} ({e.StartTime:yyyy/MM/dd HH:mm})" +
                (string.IsNullOrEmpty(e.Location) ? "" : $" @ {e.Location}")));

        var newsSummary = news.Count == 0
            ? "No relevant news topics."
            : string.Join("\n", news.Take(5).Select(n => $"- {n.Title}"));

        var displayInfo = DisplayHelper.GetDisplayInfo();
        var context = new PromptContext
        {
            EventSummary = eventSummary,
            NewsSummary = newsSummary,
            AtmosphereKeywords = [.. config.InterestKeywords],
            ImageSize = displayInfo.Size,
            AspectRatio = displayInfo.AspectRatio,
            AdditionalConstraints = string.IsNullOrWhiteSpace(config.UserPrompt)
                ? null
                : config.UserPrompt,
            OgpImageUrls = news.Where(n => n.OgpImageUrl != null)
                               .Select(n => n.OgpImageUrl!)
                               .Take(3)
                               .ToList(),
        };

        return new ContextBuildResult
        {
            PromptContext = context,
            CalendarEvents = events,
            NewsTopics = news,
        };
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
