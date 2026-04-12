namespace WondayWall.Models;

public record HistoryItem
{
    public DateTimeOffset ExecutedAt { get; init; }
    public bool IsSuccess { get; init; }
    public string? ErrorSummary { get; init; }
    public string? AppliedImagePath { get; init; }
    public List<CalendarEventItem>? UsedCalendarEvents { get; init; }
    public List<NewsTopicItem>? UsedNewsTopics { get; init; }
}
