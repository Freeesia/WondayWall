namespace WondayWall.Models;

public enum AppDistributionKind
{
    MicrosoftStoreMsix,
    MsiInstalled,
    Portable,
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
