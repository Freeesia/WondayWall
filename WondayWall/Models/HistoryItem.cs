namespace WondayWall.Models;

public record HistoryItem(
    DateTime ExecutedAt,
    bool IsSuccess,
    string? ErrorSummary = null,
    string? AppliedImagePath = null,
    List<CalendarEventItem>? UsedCalendarEvents = null,
    List<NewsTopicItem>? UsedNewsTopics = null,
    GoogleAiServiceTier? ServiceTier = null,
    bool IsSkipped = false);
