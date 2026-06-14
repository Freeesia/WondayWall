using System.ComponentModel;
using System.IO;
using Windows.ApplicationModel;
using Windows.Win32;
using Windows.Win32.Foundation;
using WondayWall.Models;

namespace WondayWall.Utils;

public static class AppDistributionUtility
{
    private const int AppModelErrorNoPackage = 15700;

    public static AppDistributionKind Detect()
    {
        if (IsRunningAsMicrosoftStoreMsix())
            return AppDistributionKind.MicrosoftStoreMsix;

        return IsMsiInstallPath()
            ? AppDistributionKind.MsiInstalled
            : AppDistributionKind.Portable;
    }

    public static bool HasPackageIdentity()
        => TryGetPackageFullName(out _);

    public static bool IsRunningAsMicrosoftStoreMsix()
    {
        if (!TryGetPackageFullName(out _))
            return false;

        return Package.Current.SignatureKind == PackageSignatureKind.Store;
    }

    private static bool TryGetPackageFullName(out string? packageFullName)
    {
        packageFullName = null;

        uint length = 0;
        var result = PInvoke.GetCurrentPackageFullName(ref length, Span<char>.Empty);

        if ((int)result == AppModelErrorNoPackage)
            return false;

        if (result != WIN32_ERROR.ERROR_INSUFFICIENT_BUFFER)
            throw new Win32Exception((int)result);

        var buffer = new char[length];
        result = PInvoke.GetCurrentPackageFullName(ref length, buffer);

        if (result != WIN32_ERROR.ERROR_SUCCESS)
            throw new Win32Exception((int)result);

        var characterCount = length > 0 ? checked((int)length - 1) : 0;
        packageFullName = new string(buffer, 0, characterCount);
        return true;
    }

    private static bool IsMsiInstallPath()
    {
        var processPath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(processPath))
            return false;

        var processDirectory = Path.GetDirectoryName(processPath);
        if (string.IsNullOrWhiteSpace(processDirectory))
            return false;

        return string.Equals(
            Path.GetFullPath(processDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            Path.GetFullPath(PathUtility.AppDataDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            StringComparison.OrdinalIgnoreCase);
    }
}
