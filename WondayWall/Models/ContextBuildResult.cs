namespace WondayWall.Models;

public record ContextBuildResult(
    PromptContext PromptContext,
    List<CalendarEventItem> CalendarEvents,
    List<NewsTopicItem> NewsTopics);
