using System.Text.Json.Serialization;
using WondayWall.ComponentModel;

namespace WondayWall.Models;

public class AppConfig
{
    [CredentialSecret]
    public string GoogleAiApiKey { get; set; } = string.Empty;
    public List<string> TargetCalendarIds { get; set; } = [];
    public List<string> RssSources { get; set; } = [];
    public string UserPrompt { get; set; } = string.Empty;
    /// <summary>自動更新スケジュール</summary>
    public UpdateSchedule Schedule { get; set; } = UpdateSchedule.OnceADay;
    /// <summary>旧バージョンとの互換性のためのフィールド。マイグレーション後は null になる。</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? RunsPerDay { get; set; } = null;
    /// <summary>タスクスケジューラ実行時、変化がなければ生成をスキップする</summary>
    public bool SkipGenerationWhenNoChanges { get; set; } = false;
    /// <summary>デスクトップ壁紙に加えてロック画面も更新する</summary>
    public bool UpdateLockScreen { get; set; } = false;
}
