namespace WondayWall.Models;

public record PromptGenerationResult(
    string ImagePrompt,
    IReadOnlyList<NewsTopicItem> SelectedNewsTopics,
    IReadOnlyList<string> SelectedNewsIds,
    GoogleAiServiceTier ServiceTier);
