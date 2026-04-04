namespace WondayWall.Models;

public class AppConfig
{
    public string GoogleAiApiKey { get; set; } = string.Empty;
    public string GoogleAiModelName { get; set; } = "gemini-2.0-flash-preview-image-generation";
    public string GoogleCalendarClientId { get; set; } = string.Empty;
    public string GoogleCalendarClientSecret { get; set; } = string.Empty;
    public List<string> TargetCalendarIds { get; set; } = [];
    public List<string> InterestKeywords { get; set; } = [];
    public List<string> RssSources { get; set; } = [];
    public int UpdateIntervalHours { get; set; } = 6;
    public string ImageSavePath { get; set; } = string.Empty;
    public bool EnableLogging { get; set; } = true;
    public string ImageSize { get; set; } = "1920x1080";
}
