namespace WondayWall.Utils;

public static class TimeHelper
{
    private static readonly TimeZoneInfo JapanTimeZone =
        TimeZoneInfo.FindSystemTimeZoneById("Tokyo Standard Time");

    public static DateTimeOffset NowInJapan()
    {
        var utcNow = DateTimeOffset.UtcNow;
        return TimeZoneInfo.ConvertTime(utcNow, JapanTimeZone);
    }

    public static DateTimeOffset ToJapanTime(DateTimeOffset value)
    {
        return TimeZoneInfo.ConvertTime(value, JapanTimeZone);
    }

    public static string FormatJapanTime(DateTimeOffset value)
    {
        var jst = ToJapanTime(value);
        return jst.ToString("yyyy/MM/dd HH:mm (JST)");
    }
}
