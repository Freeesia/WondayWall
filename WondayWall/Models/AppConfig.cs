namespace WondayWall.Models;

public class AppConfig
{
    public string GoogleAiApiKey { get; set; } = string.Empty;
    public List<string> TargetCalendarIds { get; set; } = [];
    public List<string> RssSources { get; set; } = [];
    public int UpdateIntervalHours { get; set; } = 6;
    public string UserPrompt { get; set; } = string.Empty;
    /// <summary>直前に生成した壁紙をベースにして新しい壁紙を生成するかどうか</summary>
    public bool UseCurrentWallpaperAsBase { get; set; } = false;
}
