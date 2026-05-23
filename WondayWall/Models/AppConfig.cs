using System.Text.Json;
using System.Text.Json.Serialization;
using WondayWall.ComponentModel;
using WondayWall.Utils;

namespace WondayWall.Models;

public class AppConfig : IJsonOnDeserialized
{
    [CredentialSecret]
    public string GoogleAiApiKey { get; set; } = string.Empty;
    public List<string> TargetCalendarIds { get; set; } = [];
    public List<string> RssSources { get; set; } = [];
    public string UserPrompt { get; set; } = string.Empty;
    /// <summary>自動更新スケジュール</summary>
    public UpdateSchedule Schedule { get; set; } = UpdateSchedule.OnceADay;
    /// <summary>タスクスケジューラ実行時、変化がなければ生成をスキップする</summary>
    public bool SkipGenerationWhenNoChanges { get; set; } = false;
    /// <summary>デスクトップ壁紙に加えてロック画面も更新する</summary>
    public bool UpdateLockScreen { get; set; } = false;

    /// <summary>旧バージョンの未知フィールドを捕捉する（マイグレーション後は null にクリアする）</summary>
    [JsonExtensionData]
    public Dictionary<string, JsonElement>? ExtensionData { get; set; }

    /// <summary>デシリアライゼーション完了時に旧バージョンのフィールドを新フィールドへ移行する</summary>
    void IJsonOnDeserialized.OnDeserialized()
    {
        // runsPerDay が設定されていた旧バージョンからのマイグレーション
        if (ExtensionData?.TryGetValue("runsPerDay", out var element) == true
            && element.TryGetInt32(out var runsPerDay))
        {
            Schedule = ScheduleHelper.MigrateFromRunsPerDay(runsPerDay);
        }
        ExtensionData = null;
    }
}
