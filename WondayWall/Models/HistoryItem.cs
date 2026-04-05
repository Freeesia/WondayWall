namespace WondayWall.Models;

public class HistoryItem
{
    public DateTimeOffset ExecutedAt { get; set; }
    public bool IsSuccess { get; set; }
    public string? ErrorSummary { get; set; }
    public string? AppliedImagePath { get; set; }
}
