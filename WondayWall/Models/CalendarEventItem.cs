namespace WondayWall.Models;

public class CalendarEventItem
{
    public string Title { get; set; } = string.Empty;
    public DateTimeOffset StartTime { get; set; }
    public DateTimeOffset? EndTime { get; set; }
    public string? Location { get; set; }
    public string? Description { get; set; }
}
