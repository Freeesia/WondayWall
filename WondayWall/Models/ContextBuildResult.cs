namespace WondayWall.Models;

public class ContextBuildResult
{
    public PromptContext PromptContext { get; set; } = new();
    public List<CalendarEventItem> CalendarEvents { get; set; } = [];
    public List<NewsTopicItem> NewsTopics { get; set; } = [];
}
