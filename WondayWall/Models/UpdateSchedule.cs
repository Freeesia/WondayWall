namespace WondayWall.Models;

/// <summary>壁紙の自動更新スケジュール</summary>
public enum UpdateSchedule
{
    /// <summary>週1回（月曜 7:00）</summary>
    OnceAWeek = 0,
    /// <summary>週2回（月曜・木曜 7:00）</summary>
    TwiceAWeek = 1,
    /// <summary>週3回（月曜・水曜・金曜 7:00）</summary>
    ThreeTimesAWeek = 2,
    /// <summary>1日1回（0:00）</summary>
    OnceADay = 3,
    /// <summary>1日3回（朝7:00・昼12:00・晩18:00）</summary>
    ThreeTimesADay = 4,
}
