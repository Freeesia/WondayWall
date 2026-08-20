namespace WondayWall.Models;

public record WidgetNewsEntry(
    int Index,
    string Title,
    string? Url,
    DateTime? PublishedAt);
