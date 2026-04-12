namespace WondayWall.Models;

public record GeneratedImageInfo(
    string FilePath,
    DateTimeOffset GeneratedAt,
    string UsedPrompt,
    PromptContext? SourceContext = null);
