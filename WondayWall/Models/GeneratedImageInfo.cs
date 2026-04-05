namespace WondayWall.Models;

public class GeneratedImageInfo
{
    public string FilePath { get; set; } = string.Empty;
    public DateTimeOffset GeneratedAt { get; set; }
    public string UsedPrompt { get; set; } = string.Empty;
    public PromptContext? SourceContext { get; set; }
}
