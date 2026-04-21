namespace WondayWall.Models;

public class AppConfig
{
    public string GoogleAiApiKey { get; set; } = string.Empty;
    public List<string> TargetCalendarIds { get; set; } = [];
    public List<string> RssSources { get; set; } = [];
    public string UserPrompt { get; set; } = string.Empty;
    /// <summary>1日あたりの自動更新回数</summary>
    public int RunsPerDay { get; set; } = 1;
    /// <summary>直前に生成した壁紙をベースにして新しい壁紙を生成するかどうか</summary>
    public bool UseCurrentWallpaperAsBase { get; set; } = false;
    /// <summary>タスクスケジューラ実行時、変化がなければ生成をスキップする</summary>
    public bool SkipGenerationWhenNoChanges { get; set; } = false;
    /// <summary>デスクトップ壁紙に加えてロック画面も更新する</summary>
    public bool UpdateLockScreen { get; set; } = false;
}
