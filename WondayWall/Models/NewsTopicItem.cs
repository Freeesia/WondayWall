namespace WondayWall.Models;

public record NewsTopicItem(
    string Title,
    string? Summary = null,
    string? Url = null,
    DateTime? PublishedAt = null,
    string? OgpImageUrl = null);
