namespace WondayWall.Models;

public record GeneratedImageInfo(
    string FilePath,
    DateTime GeneratedAt,
    string UsedPrompt,
    PromptContext? SourceContext = null);
