using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.ServiceModel.Syndication;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Calendar.v3;
using Google.Apis.Calendar.v3.Data;
using Google.Apis.Services;
using Google.Apis.Util.Store;
using WondayWall.Models;

namespace WondayWall.Services;

public class ContextService(AppConfigService configService)
{
    private CalendarService? _calendarService;

    public async Task<List<CalendarEventItem>> FetchCalendarEventsAsync(CancellationToken ct = default)
    {
        var config = configService.Current;
        var events = new List<CalendarEventItem>();

        if (string.IsNullOrWhiteSpace(config.GoogleCalendarClientId) ||
            string.IsNullOrWhiteSpace(config.GoogleCalendarClientSecret))
            return events;

        try
        {
            var calSvc = await GetCalendarServiceAsync(config, ct);
            var now = DateTime.UtcNow;
            var end = now.AddDays(7);

            var calendarIds = config.TargetCalendarIds.Count > 0
                ? config.TargetCalendarIds
                : ["primary"];

            foreach (var calId in calendarIds)
            {
                var request = calSvc.Events.List(calId);
                request.TimeMinDateTimeOffset = now;
                request.TimeMaxDateTimeOffset = end;
                request.SingleEvents = true;
                request.OrderBy = EventsResource.ListRequest.OrderByEnum.StartTime;

                var result = await request.ExecuteAsync(ct);
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

                    events.Add(new CalendarEventItem
                    {
                        Title = ev.Summary ?? "(no title)",
                        StartTime = start,
                        EndTime = endTime,
                        Location = ev.Location,
                        Description = ev.Description,
                    });
                }
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Calendar fetch error: {ex.Message}");
        }

        return events;
    }

    public async Task<List<NewsTopicItem>> FetchNewsAsync(CancellationToken ct = default)
    {
        var config = configService.Current;
        var topics = new List<NewsTopicItem>();

        if (config.RssSources.Count == 0)
            return topics;

        using var httpClient = new HttpClient();
        httpClient.Timeout = TimeSpan.FromSeconds(30);

        foreach (var rssUrl in config.RssSources)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                var xml = await httpClient.GetStringAsync(rssUrl, ct);
                using var reader = XmlReader.Create(new StringReader(xml));
                var feed = SyndicationFeed.Load(reader);

                foreach (var item in feed.Items)
                {
                    var title = item.Title?.Text ?? string.Empty;
                    var summary = item.Summary?.Text;
                    var url = item.Links.FirstOrDefault()?.Uri.ToString();

                    var matched = config.InterestKeywords
                        .Where(k => title.Contains(k, StringComparison.OrdinalIgnoreCase)
                                 || (summary?.Contains(k, StringComparison.OrdinalIgnoreCase) ?? false))
                        .ToList();

                    if (config.InterestKeywords.Count == 0 || matched.Count > 0)
                    {
                        topics.Add(new NewsTopicItem
                        {
                            Title = title,
                            Summary = summary,
                            Url = url,
                            FetchedAt = DateTimeOffset.UtcNow,
                            MatchedKeywords = matched,
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"RSS fetch error [{rssUrl}]: {ex.Message}");
            }
        }

        return topics;
    }

    public async Task<PromptContext> BuildPromptContextAsync(CancellationToken ct = default)
    {
        var config = configService.Current;
        var eventsTask = FetchCalendarEventsAsync(ct);
        var newsTask = FetchNewsAsync(ct);

        await Task.WhenAll(eventsTask, newsTask);

        var events = await eventsTask;
        var news = await newsTask;

        var eventSummary = events.Count == 0
            ? "No upcoming calendar events."
            : string.Join("\n", events.Take(5).Select(e =>
                $"- {e.Title} ({e.StartTime:yyyy/MM/dd HH:mm})" +
                (string.IsNullOrEmpty(e.Location) ? "" : $" @ {e.Location}")));

        var newsSummary = news.Count == 0
            ? "No relevant news topics."
            : string.Join("\n", news.Take(5).Select(n => $"- {n.Title}"));

        return new PromptContext
        {
            EventSummary = eventSummary,
            NewsSummary = newsSummary,
            AtmosphereKeywords = [.. config.InterestKeywords],
            ImageSize = config.ImageSize,
        };
    }

    private async Task<CalendarService> GetCalendarServiceAsync(AppConfig config, CancellationToken ct)
    {
        if (_calendarService != null)
            return _calendarService;

        var credPath = Path.Combine(
            System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
            "WondayWall", "calendar-token");

        var secrets = new ClientSecrets
        {
            ClientId = config.GoogleCalendarClientId,
            ClientSecret = config.GoogleCalendarClientSecret,
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
