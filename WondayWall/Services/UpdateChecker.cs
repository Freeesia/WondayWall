using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Windows.Interop;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Toolkit.Uwp.Notifications;
using Nito.AsyncEx;
using Octokit;
using Windows.Services.Store;
using Windows.UI.Notifications;
using Windows.Win32;
using Windows.Win32.System.Recovery;
using WinRT.Interop;
using WondayWall.Models;
using WondayWall.Utils;
using AppPackageVersion = Windows.ApplicationModel.PackageVersion;
using AppResources = WondayWall.Properties.Resources;

namespace WondayWall.Services;

public class UpdateChecker : BackgroundService
{
    private const string Owner = "Freeesia";
    private const string Repository = "WondayWall";
    private const string HttpClientName = "WondayWallUpdate";
    private const string SourceArgument = nameof(UpdateChecker);
    private const string ActionArgument = "action";
    private const string InstallAction = "install";
    private const string OpenReleaseNotesAction = "open-release-notes";
    private const string SkipAction = "skip";

    private static readonly string UpdateInfoPath = Path.Combine(PathUtility.AppDataDirectory, "update.json");

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IGitHubClient _gitHubClient;
    private readonly ILogger<UpdateChecker> _logger;
    private readonly AsyncLock _checking = new();
    private readonly Version _currentVersion;
    private readonly AppDistributionKind _distributionKind;

    public event EventHandler? UpdateAvailable;

    public bool IsInstalled { get; }
    public bool ShowUpdateControls => _distributionKind is not AppDistributionKind.Portable;
    public bool HasUpdate { get; private set; }
    public string? LatestVersion { get; private set; }

    public UpdateChecker(
        IHttpClientFactory httpClientFactory,
        IGitHubClient gitHubClient,
        ILogger<UpdateChecker> logger)
    {
        _httpClientFactory = httpClientFactory;
        _gitHubClient = gitHubClient;
        _logger = logger;

        var assemblyName = Assembly.GetExecutingAssembly().GetName();
        _currentVersion = GetCurrentVersion(assemblyName);
        _distributionKind = AppDistributionUtility.Detect();
        IsInstalled = _distributionKind is not AppDistributionKind.Portable;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (_distributionKind == AppDistributionKind.Portable)
        {
            _logger.LogInformation("インストール済みアプリではないため更新チェックをスキップしました");
            return;
        }

        ToastNotificationManagerCompat.OnActivated += ToastNotificationManagerCompat_OnActivated;
        try
        {
            try
            {
                if (_distributionKind == AppDistributionKind.MicrosoftStoreMsix)
                    await CheckCoreStoreAsync(stoppingToken).ConfigureAwait(false);
                else
                    await CheckCoreGitHubAsync(forceRefresh: false, stoppingToken).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is not OperationCanceledException || !stoppingToken.IsCancellationRequested)
            {
                _logger.LogWarning(ex, "起動時の更新チェックに失敗しました");
            }

            await Task.Delay(Timeout.InfiniteTimeSpan, stoppingToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
        }
        finally
        {
            ToastNotificationManagerCompat.OnActivated -= ToastNotificationManagerCompat_OnActivated;
            try
            {
                ToastNotificationManagerCompat.History.Clear();
                ToastNotificationManagerCompat.Uninstall();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "更新通知の終了処理に失敗しました");
            }
        }
    }

    public Task CheckAsync(CancellationToken ct = default)
    {
        if (!ShowUpdateControls)
        {
            _logger.LogInformation("インストール済みアプリではないため更新チェックをスキップしました");
            return Task.CompletedTask;
        }

        if (_distributionKind == AppDistributionKind.MicrosoftStoreMsix)
            return CheckCoreStoreAsync(ct);
        else
            return CheckCoreGitHubAsync(forceRefresh: true, ct);
    }

    public async void InstallUpdate()
    {
        if (_distributionKind == AppDistributionKind.MicrosoftStoreMsix)
        {
            var ownerWindow = System.Windows.Application.Current?.MainWindow;
            if (ownerWindow is null)
            {
                _logger.LogWarning("メインウィンドウが見つからないため Store 更新をスキップしました");
                return;
            }

            try
            {
                var storeContext = StoreContext.GetDefault();
                var hwnd = new WindowInteropHelper(ownerWindow).Handle;
                InitializeWithWindow.Initialize(storeContext, hwnd);

                var updates = await storeContext.GetAppAndOptionalStorePackageUpdatesAsync();
                if (updates.Count == 0)
                {
                    _logger.LogInformation("更新は見つかりませんでした");
                    return;
                }

                if (PInvoke.RegisterApplicationRestart(string.Empty, REGISTER_APPLICATION_RESTART_FLAGS.RESTART_NO_REBOOT) < 0)
                {
                    _logger.LogWarning("アプリケーションの再起動登録に失敗しました");
                }
                var result = await storeContext.RequestDownloadAndInstallStorePackageUpdatesAsync(updates);
                if (result.OverallState == StorePackageUpdateState.Completed)
                {
                    _logger.LogInformation("更新が完了しました");
                    return;
                }
                _logger.LogWarning("Store 更新の結果: {Result}", result.OverallState);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Store 更新処理に失敗しました");
            }
        }
        else
        {
            var updateInfo = LoadUpdateInfo();
            if (updateInfo?.Path is not { Length: > 0 } installerPath || !File.Exists(installerPath))
            {
                _logger.LogWarning("インストーラーが見つからないため更新を開始できませんでした");
                return;
            }

            var startInfo = new ProcessStartInfo("msiexec")
            {
                UseShellExecute = false,
            };
            startInfo.ArgumentList.Add("/i");
            startInfo.ArgumentList.Add(installerPath);
            Process.Start(startInfo);
        }
    }

    public void OpenReleaseNotes()
    {
        var url = _distributionKind == AppDistributionKind.MsiInstalled
            ? LoadUpdateInfo()?.Url
            : null;

        // Store MSIX を含む非 MSI 配布では更新メタ情報を持たないため、GitHub のリリース一覧へフォールバックする
        if (string.IsNullOrWhiteSpace(url))
            url = AppLinks.ReleaseNotes;

        Process.Start(new ProcessStartInfo(url)
        {
            UseShellExecute = true,
        });
    }

    public Task SkipVersionAsync(CancellationToken ct = default)
    {
        var updateInfo = LoadUpdateInfo();
        if (updateInfo is null)
            return Task.CompletedTask;

        SaveUpdateInfo(updateInfo with { CheckedAt = DateTime.UtcNow, Skip = true });
        SetUpdateState(updateInfo.Version, hasUpdate: false);
        return Task.CompletedTask;
    }

    private void ShowUpdateNotification(string? version, bool suppressPopup)
    {
        // Store 経由の更新はバージョンが取得できないため、その場合はバージョンなしの文言にする
        var title = version is not null
            ? AppResources.Format(AppResources.UpdateNotificationTitle, version)
            : AppResources.UpdateNotificationTitleUnknownVersion;

        var builder = new ToastContentBuilder()
            .AddText(title, AdaptiveTextStyle.Title)
            .AddText(AppResources.UpdateNotificationMessage)
            .AddArgument(SourceArgument)
            .AddButton(new ToastButton()
                .SetContent(AppResources.UpdateInstallButton)
                .AddArgument(ActionArgument, InstallAction))
            .AddButton(new ToastButton()
                .SetContent(AppResources.CheckUpdateNotes)
                .AddArgument(ActionArgument, OpenReleaseNotesAction)
                .SetBackgroundActivation());

        if (version is not null)
            builder.AddArgument("version", version);

        var skipArguments = ToastArguments.Parse(builder.Content.Launch);
        skipArguments.Add(ActionArgument, SkipAction);
        builder.Content.Actions.ContextMenuItems.Add(new(AppResources.UpdateSkipVersion, skipArguments.ToString()));

        builder.Show(toast =>
        {
            toast.ExpiresOnReboot = true;
            toast.NotificationMirroring = NotificationMirroring.Disabled;
            toast.SuppressPopup = suppressPopup;
        });
    }

    private async void ToastNotificationManagerCompat_OnActivated(ToastNotificationActivatedEventArgsCompat e)
    {
        try
        {
            var args = ToastArguments.Parse(e.Argument);
            if (!args.Contains(SourceArgument))
                return;

            if (!args.Contains(ActionArgument))
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() => System.Windows.Application.Current.MainWindow?.Show());
                return;
            }

            var action = args.Get(ActionArgument);
            switch (action)
            {
                case InstallAction:
                    // Store版は WindowInteropHelper でウィンドウハンドルを取得するため、UIスレッドから呼び出す
                    System.Windows.Application.Current?.Dispatcher.Invoke(InstallUpdate);
                    break;
                case OpenReleaseNotesAction:
                    OpenReleaseNotes();
                    // Store 経由の更新通知には version 引数が付与されないため、その場合は null のままでよい
                    args.TryGetValue("version", out string? version);
                    ShowUpdateNotification(version, suppressPopup: true);
                    break;
                case SkipAction:
                    await SkipVersionAsync().ConfigureAwait(false);
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "更新通知の操作処理に失敗しました");
        }
    }

    private async Task CheckCoreGitHubAsync(bool forceRefresh, CancellationToken ct)
    {
        using (await _checking.LockAsync(ct).ConfigureAwait(false))
        {
            var updateInfo = LoadUpdateInfo();
            if (!forceRefresh && TryUseCachedUpdateInfo(updateInfo))
                return;

            var release = await _gitHubClient.Repository.Release.GetLatest(Owner, Repository).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested();

            var versionText = GetReleaseVersionText(release);
            if (!TryParseVersion(versionText, out var releaseVersion))
            {
                _logger.LogWarning("リリースバージョンを解析できませんでした: {Version}", versionText);
                return;
            }

            if (releaseVersion <= _currentVersion)
            {
                _logger.LogInformation("アプリケーションは最新バージョンです: {Version}", releaseVersion);
                SaveUpdateInfo(new(releaseVersion.ToString(), release.HtmlUrl, null, DateTime.UtcNow, false));
                SetUpdateState(null, hasUpdate: false);
                return;
            }

            var asset = release.Assets.FirstOrDefault(static a => a.Name.EndsWith(".msi", StringComparison.OrdinalIgnoreCase));
            if (asset is null)
            {
                _logger.LogWarning("更新用 MSI がリリースアセットに見つかりませんでした");
                return;
            }

            var installerPath = await DownloadInstallerAsync(asset, ct).ConfigureAwait(false);
            var latestUpdateInfo = new UpdateInfo(releaseVersion.ToString(), release.HtmlUrl, installerPath, DateTime.UtcNow, false);
            SaveUpdateInfo(latestUpdateInfo);
            SetUpdateState(latestUpdateInfo.Version, hasUpdate: true);
        }
    }

    private async Task CheckCoreStoreAsync(CancellationToken ct)
    {
        using (await _checking.LockAsync(ct).ConfigureAwait(false))
        {
            var storeContext = StoreContext.GetDefault();
            var updates = await storeContext.GetAppAndOptionalStorePackageUpdatesAsync();
            ct.ThrowIfCancellationRequested();

            if (updates.Count == 0)
            {
                _logger.LogDebug("更新は見つかりませんでした");
                SetUpdateState(null, hasUpdate: false);
            }
            else
            {
                _logger.LogInformation("Microsoft Storeに更新がありました");
                // ストア経由では最新バージョン番号を取得する手段がないため、バージョンを表示せずに更新ありとして扱う
                SetUpdateState(null, hasUpdate: true);
            }
        }
    }

    private bool TryUseCachedUpdateInfo(UpdateInfo? updateInfo)
    {
        if (updateInfo is null || updateInfo.CheckedAt < DateTime.UtcNow.AddDays(-1))
            return false;

        if (!TryParseVersion(updateInfo.Version, out var cachedVersion) || cachedVersion <= _currentVersion)
        {
            SetUpdateState(null, hasUpdate: false);
            return true;
        }

        if (updateInfo.Skip)
        {
            SetUpdateState(updateInfo.Version, hasUpdate: false);
            return true;
        }

        if (updateInfo.Path is { Length: > 0 } installerPath && File.Exists(installerPath))
        {
            SetUpdateState(updateInfo.Version, hasUpdate: true);
            return true;
        }

        return false;
    }

    private async Task<string> DownloadInstallerAsync(ReleaseAsset asset, CancellationToken ct)
    {
        var dir = Path.Combine(Path.GetTempPath(), Repository);
        Directory.CreateDirectory(dir);

        var installerPath = Path.Combine(dir, Path.GetFileName(asset.Name));
        if (File.Exists(installerPath))
        {
            _logger.LogInformation("インストーラーはすでにダウンロードされています: {InstallerPath}", installerPath);
            return installerPath;
        }

        var tempPath = Path.Combine(dir, Path.GetRandomFileName());
        try
        {
            var client = _httpClientFactory.CreateClient(HttpClientName);
            using var response = await client
                .GetAsync(asset.BrowserDownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct)
                .ConfigureAwait(false);
            response.EnsureSuccessStatusCode();

            await using (var source = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false))
            {
                await using var destination = File.Create(tempPath);
                await source.CopyToAsync(destination, ct).ConfigureAwait(false);
            }

            if (new FileInfo(tempPath).Length == 0)
                throw new InvalidOperationException("GitHub release asset のダウンロード結果が空です");

            File.Move(tempPath, installerPath, overwrite: true);
            _logger.LogInformation("インストーラーをダウンロードしました: {InstallerPath}", installerPath);
            return installerPath;
        }
        finally
        {
            if (File.Exists(tempPath))
                File.Delete(tempPath);
        }
    }

    private UpdateInfo? LoadUpdateInfo()
        => JsonFileHelper.Load<UpdateInfo>(UpdateInfoPath);

    private static void SaveUpdateInfo(UpdateInfo updateInfo)
        => JsonFileHelper.Save(UpdateInfoPath, updateInfo);

    private void SetUpdateState(string? latestVersion, bool hasUpdate)
    {
        var changed = HasUpdate != hasUpdate || LatestVersion != latestVersion;
        HasUpdate = hasUpdate;
        LatestVersion = latestVersion;

        if (changed)
        {
            UpdateAvailable?.Invoke(this, EventArgs.Empty);
            if (hasUpdate)
            {
                try
                {
                    // Store 経由の更新は latestVersion が null になり得るが、その場合もバージョンなしの通知を表示する
                    ShowUpdateNotification(latestVersion, suppressPopup: false);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "更新通知の表示に失敗しました");
                }
            }
        }
    }

    private static string? GetReleaseVersionText(Release release)
        => string.IsNullOrWhiteSpace(release.TagName) ? release.Name : release.TagName;

    private static Version GetCurrentVersion(AssemblyName assemblyName)
    {
        var processPath = Environment.ProcessPath;
        var fileVersion = processPath is null
            ? null
            : FileVersionInfo.GetVersionInfo(processPath).FileVersion;

        return TryParseVersion(fileVersion, out var version)
            ? version
            : assemblyName.Version ?? new Version(0, 0, 0, 0);
    }

    private static bool TryParseVersion(string? value, out Version version)
    {
        version = new Version(0, 0, 0, 0);
        if (string.IsNullOrWhiteSpace(value))
            return false;

        var normalized = value.Trim().TrimStart('v', 'V');
        var metadataIndex = normalized.IndexOf('+', StringComparison.Ordinal);
        if (metadataIndex >= 0)
            normalized = normalized[..metadataIndex];

        var prereleaseIndex = normalized.IndexOf('-', StringComparison.Ordinal);
        if (prereleaseIndex >= 0)
            normalized = normalized[..prereleaseIndex];

        if (!Version.TryParse(normalized, out var parsedVersion))
            return false;

        version = parsedVersion;
        return true;
    }

    private static string ToVersionString(AppPackageVersion version)
        => $"{version.Major}.{version.Minor}.{version.Build}.{version.Revision}";

}
