using System.Globalization;
using System.Windows.Data;

namespace WondayWall.Utils;

public sealed class StringFormatConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => parameter is string format ? string.Format(culture, format, value) : value;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => Binding.DoNothing;
}
