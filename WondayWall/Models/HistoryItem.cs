namespace WondayWall.Models;

public record HistoryItem(
    DateTime ExecutedAt,
    bool IsSuccess,
    string? ErrorSummary = null,
    string? AppliedImagePath = null,
    List<CalendarEventItem>? UsedCalendarEvents = null,
    List<NewsTopicItem>? UsedNewsTopics = null,
    bool IsSkipped = false,
    bool WasUpscaled = false,
    string? OriginalGeneratedImagePath = null,
    string? RequestedUpscaleMode = null,
    string? ActualUpscaleMethod = null);
