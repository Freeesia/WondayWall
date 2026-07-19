namespace WondayWall.Models;

#if DEBUG
/// <summary>繝・ヰ繝・げ繝薙Ν繝牙ｰら畑縺ｮ讀懆ｨｼ逕ｨ險ｭ螳壹ゅΜ繝ｪ繝ｼ繧ｹ繝薙Ν繝峨↓縺ｯ蜷ｫ繧√↑縺・・/summary>
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
#endif
