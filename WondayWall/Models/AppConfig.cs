namespace WondayWall.Models;

public class AppConfig
{
    public string GoogleAiApiKey { get; set; } = string.Empty;
    public List<string> RssSources { get; set; } = [];
    public string UserPrompt { get; set; } = string.Empty;
    /// <summary>1日あたりの自動更新回数</summary>
    public int RunsPerDay { get; set; } = 4;
    /// <summary>タスクスケジューラ実行時、変化がなければ生成をスキップする</summary>
    public bool SkipGenerationWhenNoChanges { get; set; } = false;
    /// <summary>デスクトップ壁紙に加えてロック画面も更新する</summary>
    public bool UpdateLockScreen { get; set; } = false;
}
