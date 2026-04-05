namespace WondayWall.Models;

public class NewsTopicItem
{
    public string Title { get; set; } = string.Empty;
    public string? Summary { get; set; }
    public string? Url { get; set; }
    public DateTimeOffset FetchedAt { get; set; }
    public List<string> MatchedKeywords { get; set; } = [];
}
