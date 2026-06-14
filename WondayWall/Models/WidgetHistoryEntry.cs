namespace WondayWall.Models;

public record WidgetHistoryEntry(
    string HistoryId,
    DateTime ExecutedAt,
    string OriginalImagePath,
    string BackgroundImagePath,
    IReadOnlyList<WidgetNewsEntry> NewsItems);
