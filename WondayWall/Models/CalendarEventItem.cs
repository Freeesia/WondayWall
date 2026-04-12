namespace WondayWall.Models;

public record CalendarEventItem
{
    public string Title { get; init; } = string.Empty;
    public DateTimeOffset StartTime { get; init; }
    public DateTimeOffset? EndTime { get; init; }
    public string? Location { get; init; }
    public string? Description { get; init; }
}
