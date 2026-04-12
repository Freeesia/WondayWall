namespace WondayWall.Models;

public record NewsTopicItem(
    string Title,
    string? Summary = null,
    string? Url = null,
    DateTimeOffset? PublishedAt = null,
    string? OgpImageUrl = null);
