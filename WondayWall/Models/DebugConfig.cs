namespace WondayWall.Models;

public class DebugConfig
{
    private const int MinDelaySeconds = 1;
    private const int MaxDelaySeconds = 3600;
    private const int MinNewsCount = 0;
    private const int MaxNewsCount = 20;

    public bool UseDummyAiService { get; set; } = false;
    public int DummyPromptDelaySeconds { get; set; } = 180;
    public int DummyImageDelaySeconds { get; set; } = 600;
    public int DummyNewsCount { get; set; } = 4;

    public void Normalize()
    {
        DummyPromptDelaySeconds = Math.Clamp(DummyPromptDelaySeconds, MinDelaySeconds, MaxDelaySeconds);
        DummyImageDelaySeconds = Math.Clamp(DummyImageDelaySeconds, MinDelaySeconds, MaxDelaySeconds);
        DummyNewsCount = Math.Clamp(DummyNewsCount, MinNewsCount, MaxNewsCount);
    }
}
