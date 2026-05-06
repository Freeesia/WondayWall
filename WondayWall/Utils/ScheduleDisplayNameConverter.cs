using System.Globalization;
using System.Windows.Data;
using WondayWall.Models;

namespace WondayWall.Utils;

/// <summary>UpdateSchedule 列挙値をスケジュール表示名に変換するコンバーター</summary>
[ValueConversion(typeof(UpdateSchedule), typeof(string))]
public class ScheduleDisplayNameConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is UpdateSchedule schedule ? ScheduleHelper.GetScheduleDisplayName(schedule) : string.Empty;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
