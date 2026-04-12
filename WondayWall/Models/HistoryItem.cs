namespace WondayWall.Models;

public record HistoryItem(
    DateTimeOffset ExecutedAt,
    bool IsSuccess,
    string? ErrorSummary = null,
    string? AppliedImagePath = null,
    List<CalendarEventItem>? UsedCalendarEvents = null,
    List<NewsTopicItem>? UsedNewsTopics = null,
    bool IsSkipped = false);
