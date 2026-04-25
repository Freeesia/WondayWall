namespace WondayWall.Models;

public record GeneratedImageInfo(
    string FilePath,
    DateTime GeneratedAt,
    string UsedPrompt,
    GoogleAiServiceTier ServiceTier,
    PromptContext? SourceContext = null);
