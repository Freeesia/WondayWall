namespace WondayWall.Utils;

public static class ScheduleHelper
{
    public const int DefaultRunsPerDay = 4;

    public static IReadOnlyList<int> SupportedRunsPerDay { get; } = [1, 2, 3, 4, 6, 8, 12, 24];

    public static int NormalizeRunsPerDay(int runsPerDay)
        => SupportedRunsPerDay.Contains(runsPerDay)
            ? runsPerDay
            : DefaultRunsPerDay;

    public static TimeSpan GetInterval(int runsPerDay)
        => TimeSpan.FromHours(24 / NormalizeRunsPerDay(runsPerDay));

    public static IReadOnlyList<TimeSpan> GetSlotOffsets(int runsPerDay)
    {
        var normalizedRunsPerDay = NormalizeRunsPerDay(runsPerDay);
        var intervalHours = 24 / normalizedRunsPerDay;

        return Enumerable
            .Range(0, normalizedRunsPerDay)
            .Select(index => TimeSpan.FromHours(intervalHours * index))
            .ToArray();
    }

    public static DateTimeOffset GetLatestScheduledSlotAtOrBefore(DateTimeOffset now, int runsPerDay)
    {
        var localNow = now.ToLocalTime();
        var dayStart = new DateTimeOffset(localNow.Year, localNow.Month, localNow.Day, 0, 0, 0, localNow.Offset);
        var slotOffsets = GetSlotOffsets(runsPerDay);

        for (var i = slotOffsets.Count - 1; i >= 0; i--)
        {
            var candidate = dayStart + slotOffsets[i];
            if (candidate <= localNow)
                return candidate;
        }

        return dayStart.AddDays(-1) + slotOffsets[^1];
    }

    public static string FormatSlotTimes(int runsPerDay)
        => string.Join(
            " / ",
            GetSlotOffsets(runsPerDay)
                .Select(static offset => $"{(int)offset.TotalHours}:00"));

    public static string FormatScheduleDescription(int runsPerDay)
        => $"毎日 {FormatSlotTimes(runsPerDay)} に実行します。PC の電源断などで定刻を逃した場合だけ、次回ログオン時に補完実行します。";
}
