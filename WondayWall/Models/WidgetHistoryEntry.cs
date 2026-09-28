namespace WondayWall.Models;

public record WidgetHistoryEntry(
    string HistoryId,
    DateTime ExecutedAt,
    string BackgroundImageUri,
    IReadOnlyList<WidgetNewsEntry> NewsItems);
