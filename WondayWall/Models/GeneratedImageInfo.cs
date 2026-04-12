namespace WondayWall.Models;

public record GeneratedImageInfo
{
    public string FilePath { get; init; } = string.Empty;
    public DateTimeOffset GeneratedAt { get; init; }
    public string UsedPrompt { get; init; } = string.Empty;
    public PromptContext? SourceContext { get; init; }
}
