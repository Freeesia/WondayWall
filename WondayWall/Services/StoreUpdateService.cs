using System.Linq;
using System.Windows;
using System.Windows.Interop;
using Windows.ApplicationModel;
using Windows.Services.Store;
using WinRT.Interop;
using WondayWall.Models;

namespace WondayWall.Services;

public sealed class StoreUpdateService
{
    private readonly AppDistributionService _distributionService;

    public StoreUpdateService(AppDistributionService distributionService)
    {
        _distributionService = distributionService;
    }

    public async Task<StoreUpdateCheckResult> CheckForUpdateAsync(Window ownerWindow)
    {
        var distributionKind = _distributionService.Detect();
        if (!_distributionService.CanCheckStoreUpdate())
            return StoreUpdateCheckResult.NotSupported(distributionKind);

        var storeContext = StoreContext.GetDefault();
        var hwnd = new WindowInteropHelper(ownerWindow).Handle;
        InitializeWithWindow.Initialize(storeContext, hwnd);

        var updates = await storeContext.GetAppAndOptionalStorePackageUpdatesAsync();

        if (updates.Count == 0)
        {
            return new StoreUpdateCheckResult(
                IsSupported: true,
                HasUpdate: false,
                CurrentVersion: ToVersionString(Package.Current.Id.Version),
                LatestVersion: null,
                IsMandatory: false,
                DistributionKind: AppDistributionKind.MicrosoftStoreMsix);
        }

        // Count == 0 は上で除外済みのため先頭要素は必ず存在する。
        var appUpdate = updates[0];

        return new StoreUpdateCheckResult(
            IsSupported: true,
            HasUpdate: true,
            CurrentVersion: ToVersionString(Package.Current.Id.Version),
            LatestVersion: ToVersionString(appUpdate.Package.Id.Version),
            IsMandatory: updates.Any(x => x.Mandatory),
            DistributionKind: AppDistributionKind.MicrosoftStoreMsix);
    }

    public async Task<StorePackageUpdateResult?> RequestUpdateAsync(Window ownerWindow)
    {
        if (!_distributionService.CanCheckStoreUpdate())
            return null;

        var storeContext = StoreContext.GetDefault();
        var hwnd = new WindowInteropHelper(ownerWindow).Handle;
        InitializeWithWindow.Initialize(storeContext, hwnd);

        var updates = await storeContext.GetAppAndOptionalStorePackageUpdatesAsync();
        if (updates.Count == 0)
            return null;

        return await storeContext.RequestDownloadAndInstallStorePackageUpdatesAsync(updates);
    }

    private static string ToVersionString(PackageVersion version)
        => $"{version.Major}.{version.Minor}.{version.Build}.{version.Revision}";
}

public sealed record StoreUpdateCheckResult(
    bool IsSupported,
    bool HasUpdate,
    string? CurrentVersion,
    string? LatestVersion,
    bool IsMandatory,
    AppDistributionKind DistributionKind)
{
    public static StoreUpdateCheckResult NotSupported(AppDistributionKind distributionKind)
        => new(false, false, null, null, false, distributionKind);
}
