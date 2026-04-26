using System.Globalization;
using Avalonia.Data.Converters;

namespace WondayWall.Utils;

/// <summary>URL文字列をGoogle Faviconサービスのアイコン画像URLに変換するコンバーター</summary>
public class UrlToFaviconConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not string url || string.IsNullOrWhiteSpace(url))
            return null;

        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
            return null;

        return $"https://www.google.com/s2/favicons?sz=32&domain={uri.Host}";
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
