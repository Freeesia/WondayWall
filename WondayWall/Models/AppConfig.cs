namespace WondayWall.Models;

public class AppConfig
{
    public string GoogleAiApiKey { get; set; } = string.Empty;
    public List<string> TargetCalendarIds { get; set; } = [];
    public List<string> InterestKeywords { get; set; } = [];
    public List<string> RssSources { get; set; } = [];
    public int UpdateIntervalHours { get; set; } = 6;
    public string UserPrompt { get; set; } = string.Empty;
}
