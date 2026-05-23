using System.Globalization;
using Avalonia.Data.Converters;
using WondayWall.Models;

namespace WondayWall.Utils;

/// <summary>UpdateSchedule 列挙値をスケジュール表示名に変換するコンバーター</summary>
public class ScheduleDisplayNameConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is UpdateSchedule schedule ? ScheduleHelper.GetScheduleDisplayName(schedule) : string.Empty;

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException("ConvertBack is not supported for ScheduleDisplayNameConverter.");
}
