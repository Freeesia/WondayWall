namespace WondayWall.Models;

public record PromptContext(
    string EventSummary = "",
    string NewsSummary = "",
    string ImageSize = "1920x1080",
    string AspectRatio = "16:9",
    string? AdditionalConstraints = null)
{
    public List<string> OgpImageUrls { get; init; } = [];
}
