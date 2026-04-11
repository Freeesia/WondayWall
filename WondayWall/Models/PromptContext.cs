namespace WondayWall.Models;

public class PromptContext
{
    public string EventSummary { get; set; } = string.Empty;
    public string NewsSummary { get; set; } = string.Empty;
    public List<string> AtmosphereKeywords { get; set; } = [];
    public string ImageSize { get; set; } = "1920x1080";
    public string? AdditionalConstraints { get; set; }
    public string AspectRatio { get; set; } = "16:9";
    public List<string> OgpImageUrls { get; set; } = [];
}
