namespace WondayWall.Models;

public record HistoryItem(
    string Id = "",
    DateTime ExecutedAt = default,
    bool IsSuccess = false,
    string? ErrorSummary = null,
    string? AppliedImagePath = null,
    List<CalendarEventItem>? UsedCalendarEvents = null,
    List<NewsTopicItem>? UsedNewsTopics = null,
    GoogleAiServiceTier? ServiceTier = null,
    bool IsSkipped = false);
