using WondayWall.Models;
using AppResources = WondayWall.Properties.Resources;

namespace WondayWall.Utils;

public static class ScheduleHelper
{
    // 週次スケジュールの実行時刻（7:00）
    public static readonly TimeSpan WeeklySlotTime = TimeSpan.FromHours(7);

    // 週次スケジュールの曜日定義
    public static readonly IReadOnlyList<DayOfWeek> OnceAWeekDays = [DayOfWeek.Monday];
    public static readonly IReadOnlyList<DayOfWeek> TwiceAWeekDays = [DayOfWeek.Monday, DayOfWeek.Thursday];
    public static readonly IReadOnlyList<DayOfWeek> ThreeTimesAWeekDays = [DayOfWeek.Monday, DayOfWeek.Wednesday, DayOfWeek.Friday];

    // 1日複数回スケジュールのスロット時刻
    private static readonly IReadOnlyList<TimeSpan> OnceDaySlots = [TimeSpan.Zero];
    private static readonly IReadOnlyList<TimeSpan> ThreeTimesDaySlots =
    [
        TimeSpan.FromHours(7),   // 朝
        TimeSpan.FromHours(12),  // 昼
        TimeSpan.FromHours(18),  // 晩
    ];

    public static UpdateSchedule DefaultSchedule => UpdateSchedule.OnceADay;

    public static IReadOnlyList<UpdateSchedule> SupportedSchedules { get; } = Enum.GetValues<UpdateSchedule>();

    /// <summary>週次スケジュールかどうかを返す</summary>
    public static bool IsWeeklySchedule(UpdateSchedule schedule)
        => schedule is UpdateSchedule.OnceAWeek or UpdateSchedule.TwiceAWeek or UpdateSchedule.ThreeTimesAWeek;

    /// <summary>週次スケジュールの対象曜日一覧を返す</summary>
    public static IReadOnlyList<DayOfWeek> GetWeekDays(UpdateSchedule schedule) => schedule switch
    {
        UpdateSchedule.OnceAWeek => OnceAWeekDays,
        UpdateSchedule.TwiceAWeek => TwiceAWeekDays,
        UpdateSchedule.ThreeTimesAWeek => ThreeTimesAWeekDays,
        _ => [],
    };

    /// <summary>1日内のスロット時刻オフセット一覧を返す（週次スケジュールは WeeklySlotTime の 1 スロットのみ）</summary>
    public static IReadOnlyList<TimeSpan> GetSlotOffsets(UpdateSchedule schedule) => schedule switch
    {
        UpdateSchedule.ThreeTimesADay => ThreeTimesDaySlots,
        _ when IsWeeklySchedule(schedule) => [WeeklySlotTime],
        _ => OnceDaySlots,
    };

    /// <summary>現在時刻以前で最も直近のスケジュール済みスロットを返す</summary>
    public static DateTime GetLatestScheduledSlotAtOrBefore(DateTime now, UpdateSchedule schedule)
    {
        if (IsWeeklySchedule(schedule))
        {
            var weekDays = GetWeekDays(schedule);
            // 過去7日間を逆順に走査して直近の対象日を探す
            for (var i = 0; i <= 7; i++)
            {
                var candidate = now.Date.AddDays(-i) + WeeklySlotTime;
                if (candidate <= now && weekDays.Contains(candidate.DayOfWeek))
                    return candidate;
            }
            // フォールバック（通常は到達しない）
            return now.Date.AddDays(-7) + WeeklySlotTime;
        }
        else
        {
            var slots = GetSlotOffsets(schedule);
            var dayStart = now.Date;
            for (var i = slots.Count - 1; i >= 0; i--)
            {
                var candidate = dayStart + slots[i];
                if (candidate <= now)
                    return candidate;
            }
            return dayStart.AddDays(-1) + slots[^1];
        }
    }

    /// <summary>スケジュールの表示名を返す</summary>
    public static string GetScheduleDisplayName(UpdateSchedule schedule) => schedule switch
    {
        UpdateSchedule.OnceAWeek => AppResources.ScheduleOnceAWeek,
        UpdateSchedule.TwiceAWeek => AppResources.ScheduleTwiceAWeek,
        UpdateSchedule.ThreeTimesAWeek => AppResources.ScheduleThreeTimesAWeek,
        UpdateSchedule.OnceADay => AppResources.ScheduleOnceADay,
        UpdateSchedule.ThreeTimesADay => AppResources.ScheduleThreeTimesADay,
        _ => schedule.ToString(),
    };

    /// <summary>スケジュールの詳細説明（実行時刻を含む）を返す</summary>
    public static string FormatScheduleDescription(UpdateSchedule schedule)
    {
        if (IsWeeklySchedule(schedule))
        {
            var slotTimeStr = $"{(int)WeeklySlotTime.TotalHours}:00";
            return AppResources.Format(AppResources.ScheduleDescriptionWeekly, slotTimeStr);
        }
        else
        {
            var slotTimesStr = string.Join(
                " / ",
                GetSlotOffsets(schedule).Select(static offset => $"{(int)offset.TotalHours}:00"));
            return AppResources.Format(AppResources.ScheduleDescriptionDaily, slotTimesStr);
        }
    }

    /// <summary>旧バージョンの RunsPerDay 値から UpdateSchedule へマイグレーションする</summary>
    public static UpdateSchedule MigrateFromRunsPerDay(int runsPerDay) => runsPerDay switch
    {
        3 => UpdateSchedule.ThreeTimesADay,
        _ => UpdateSchedule.OnceADay,
    };
}
