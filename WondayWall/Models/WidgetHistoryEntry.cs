namespace WondayWall.Models;

public record WidgetHistoryEntry(
    string HistoryId,
    DateTime ExecutedAt,
    string OriginalImagePath,
    string BackgroundImageUri,
    IReadOnlyList<WidgetNewsEntry> NewsItems);
