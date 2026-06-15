namespace WondayWall.Models;

public class DebugConfig
{
    private const int MinDelaySeconds = 0;
    private const int MaxDelaySeconds = 1800;
    private const int MinNewsCount = 1;
    private const int MaxNewsCount = 10;

    public bool UseDummyAiService { get; set; } = false;
    public int DummyPromptDelaySeconds { get; set; } = 0;
    public int DummyImageDelaySeconds { get; set; } = 0;
    public int DummyNewsCount { get; set; } = 4;

    public void Normalize()
    {
        DummyPromptDelaySeconds = Math.Clamp(DummyPromptDelaySeconds, MinDelaySeconds, MaxDelaySeconds);
        DummyImageDelaySeconds = Math.Clamp(DummyImageDelaySeconds, MinDelaySeconds, MaxDelaySeconds);
        DummyNewsCount = Math.Clamp(DummyNewsCount, MinNewsCount, MaxNewsCount);
    }
}
