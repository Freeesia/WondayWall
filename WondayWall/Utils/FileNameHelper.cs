using System.IO;

namespace WondayWall.Utils;

public static class FileNameHelper
{
    public static string GenerateImageFileName(string prefix = "wallpaper", string extension = "png")
    {
        var timestamp = DateTimeOffset.Now.ToString("yyyyMMdd_HHmmss");
        return $"{prefix}_{timestamp}.{extension}";
    }

    public static string GetImageFilePath(string directory, string prefix = "wallpaper", string extension = "png")
    {
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, GenerateImageFileName(prefix, extension));
    }
}
