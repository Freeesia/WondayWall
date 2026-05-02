using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Toolkit.Uwp.Notifications;
using Nito.AsyncEx;
using Octokit;
using Windows.UI.Notifications;
using WondayWall.Models;
using WondayWall.Utils;
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

    public event EventHandler? UpdateAvailable;

    public bool IsInstalled { get; }
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
        IsInstalled = CheckInstalled();
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!IsInstalled)
        {
            _logger.LogInformation("インストール済みアプリではないため更新チェックをスキップしました");
            return;
        }

        ToastNotificationManagerCompat.OnActivated += ToastNotificationManagerCompat_OnActivated;
        try
        {
            try
            {
                await CheckCoreAsync(forceRefresh: false, stoppingToken).ConfigureAwait(false);
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
        if (!IsInstalled)
        {
            _logger.LogInformation("インストール済みアプリではないため更新チェックをスキップしました");
            return Task.CompletedTask;
        }

        return CheckCoreAsync(forceRefresh: true, ct);
    }

    public void InstallUpdate()
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

    public void OpenReleaseNotes()
    {
        var updateInfo = LoadUpdateInfo();
        var url = updateInfo?.Url;
        if (string.IsNullOrWhiteSpace(url))
        {
            _logger.LogWarning("更新情報の URL がないためリリースノートを開けませんでした");
            return;
        }

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

    private void ShowUpdateNotification(string version, bool suppressPopup)
    {
        var builder = new ToastContentBuilder()
            .AddText(AppResources.Format(AppResources.UpdateNotificationTitle, version), AdaptiveTextStyle.Title)
            .AddText(AppResources.UpdateNotificationMessage)
            .AddArgument(SourceArgument)
            .AddArgument("version", version)
            .AddButton(new ToastButton()
                .SetContent(AppResources.UpdateInstallButton)
                .AddArgument(ActionArgument, InstallAction))
            .AddButton(new ToastButton()
                .SetContent(AppResources.CheckUpdateNotes)
                .AddArgument(ActionArgument, OpenReleaseNotesAction)
                .SetBackgroundActivation());

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
                    InstallUpdate();
                    break;
                case OpenReleaseNotesAction:
                    OpenReleaseNotes();
                    if (args.TryGetValue("version", out string? version) && version is not null)
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

    private async Task CheckCoreAsync(bool forceRefresh, CancellationToken ct)
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
            SetUpdateState(latestUpdateInfo.Version, hasUpdate: true, showNotification: true);
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
            SetUpdateState(updateInfo.Version, hasUpdate: true, showNotification: true);
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

    private void SetUpdateState(string? latestVersion, bool hasUpdate, bool showNotification = false)
    {
        var changed = HasUpdate != hasUpdate || LatestVersion != latestVersion;
        HasUpdate = hasUpdate;
        LatestVersion = latestVersion;
        if (hasUpdate && showNotification && latestVersion is not null)
        {
            try
            {
                ShowUpdateNotification(latestVersion, suppressPopup: false);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "更新通知の表示に失敗しました");
            }
        }

        if (changed)
        {
            try
            {
                UpdateAvailable?.Invoke(this, EventArgs.Empty);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "更新状態の変更通知に失敗しました");
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

    private static bool CheckInstalled()
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
