using System.ComponentModel;
using System.IO;
using Windows.ApplicationModel;
using Windows.Win32;
using Windows.Win32.Foundation;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public sealed class AppDistributionService
{
    private const int AppModelErrorNoPackage = 15700;

    public AppDistributionKind Detect()
    {
        if (IsRunningAsMicrosoftStoreMsix())
            return AppDistributionKind.MicrosoftStoreMsix;

        return IsMsiInstallPath()
            ? AppDistributionKind.MsiInstalled
            : AppDistributionKind.Portable;
    }

    public bool IsRunningAsMicrosoftStoreMsix()
    {
        if (!TryGetPackageFullName(out _))
            return false;

        return Package.Current.SignatureKind == PackageSignatureKind.Store;
    }

    public bool HasPackageIdentity()
        => TryGetPackageFullName(out _);

    public bool CanCheckStoreUpdate()
        => IsRunningAsMicrosoftStoreMsix();

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

        packageFullName = new string(buffer).TrimEnd('\0');
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

        var installDirectory = PathUtility.AppDataDirectory;

        return string.Equals(
            Path.GetFullPath(processDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            Path.GetFullPath(installDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            StringComparison.OrdinalIgnoreCase);
    }
}
