namespace WondayWall.Models;

public record CalendarEventItem(
    string Title,
    DateTime StartTime,
    DateTime? EndTime = null,
    string? Location = null,
    string? Description = null);
