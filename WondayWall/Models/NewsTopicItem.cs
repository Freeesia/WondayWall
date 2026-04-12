namespace WondayWall.Models;

public record NewsTopicItem
{
    public string Title { get; init; } = string.Empty;
    public string? Summary { get; init; }
    public string? Url { get; init; }
    public DateTimeOffset? PublishedAt { get; init; }
    public string? OgpImageUrl { get; init; }
}
