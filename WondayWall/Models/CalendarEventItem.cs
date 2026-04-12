namespace WondayWall.Models;

public record CalendarEventItem(
    string Title,
    DateTimeOffset StartTime,
    DateTimeOffset? EndTime = null,
    string? Location = null,
    string? Description = null);
