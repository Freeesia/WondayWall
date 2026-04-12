namespace WondayWall.Models;

public record PromptContext
{
    public string EventSummary { get; init; } = string.Empty;
    public string NewsSummary { get; init; } = string.Empty;
    public string ImageSize { get; init; } = "1920x1080";
    public string? AdditionalConstraints { get; init; }
    public string AspectRatio { get; init; } = "16:9";
    public List<string> OgpImageUrls { get; init; } = [];
}
