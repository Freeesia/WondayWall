using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Security;
using Avalonia.Threading;
using System.Text;
using AngleSharp.Html.Parser;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Services;
using WondayWall.Utils;
using AppResources = WondayWall.Properties.Resources;

namespace WondayWall.ViewModels;

public partial class MainWindowViewModel : ObservableObject
{
    private const int MaxSiteHtmlChars = 512_000;
    private static readonly HtmlParser HtmlParser = new();

    private readonly AppConfigService _configService;
    private readonly HistoryService _historyService;
    private readonly ContextService _contextService;
    private readonly GenerationCoordinator _coordinator;
    private readonly TaskSchedulerService _taskSchedulerService;
    private readonly UpdateChecker _updateChecker;
    private readonly ILogger<MainWindowViewModel> _logger;
    private readonly IHttpClientFactory _httpClientFactory;

    [ObservableProperty]
    public partial AppConfig AppConfig { get; set; } = new();

    [ObservableProperty]
    public partial string CalendarStatus { get; set; } = AppResources.CalendarStatusNotConnected;

    [ObservableProperty]
    public partial bool IsCalendarConnected { get; set; }

    [ObservableProperty]
    public partial string LastResultMessage { get; set; } = AppResources.LastResultNoGeneration;

    [ObservableProperty]
    public partial bool IsGenerating { get; set; }

    [ObservableProperty]
    public partial bool IsTaskSchedulerEnabled { get; set; }

    [ObservableProperty]
    public partial bool ShowUpdateControls { get; set; }

    [ObservableProperty]
    public partial bool HasUpdate { get; set; }

    [ObservableProperty]
    public partial string? LatestVersion { get; set; }

    [ObservableProperty]
    public partial bool IsCheckingUpdate { get; set; }

    [ObservableProperty]
    public partial bool ShowSetupWizard { get; set; }

    [ObservableProperty]
    public partial UpdateSchedule SelectedSchedule { get; set; }

    [ObservableProperty]
    public partial GeneratedImageInfo? LastGeneratedImage { get; set; }

    [ObservableProperty]
    public partial string LastImagePreviewPath { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string NewRssSourceUrl { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string? SelectedRssSource { get; set; }

    [ObservableProperty]
    public partial PromptTemplate? SelectedPromptTemplate { get; set; }

    public ObservableCollection<CalendarEventItem> RecentEvents { get; } = [];
    public ObservableCollection<NewsTopicItem> RecentNews { get; } = [];
    public ObservableCollection<HistoryItem> History { get; } = [];
    public ObservableCollection<string> RssSources { get; } = [];
    public ObservableCollection<AvailableCalendar> AvailableCalendars { get; } = [];
    public IReadOnlyList<UpdateSchedule> AvailableScheduleOptions => ScheduleHelper.SupportedSchedules;

    /// <summary>追加プロンプトのプリセットテンプレート一覧</summary>
    public IReadOnlyList<PromptTemplate> PromptTemplates { get; } =
    [
        new(AppResources.PromptTemplateWatercolor,
            "Use a soft watercolor painting style with translucent washes, delicate brush strokes, and a gentle pastel color palette."),
        new(AppResources.PromptTemplateAnime,
            "Use a vibrant anime illustration style with bold outlines, cel-shading, and dynamic composition."),
        new(AppResources.PromptTemplatePhotorealistic,
            "Generate a photorealistic scene with natural lighting, rich textures, sharp details, and cinematic depth."),
        new(AppResources.PromptTemplateMinimalist,
            "Use a minimalist design with clean geometry, generous negative space, and a subtle two- or three-tone color palette."),
        new(AppResources.PromptTemplateDark,
            "Use a dark color scheme with deep blacks, navy blues, and charcoal grays. Add dramatic contrast with carefully placed highlights."),
        new(AppResources.PromptTemplateFantasy,
            "Create a magical fantasy atmosphere with ethereal glows, soft bokeh, mystical lighting, and dreamlike scenery."),
    ];
    public string TaskSchedulerScheduleDescription => ScheduleHelper.FormatScheduleDescription(SelectedSchedule);

    /// <summary>アセンブリのインフォメーションバージョン</summary>
    public string AppVersion { get; } =
        Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion
        ?? "0.0.0";

    public MainWindowViewModel(
        AppConfigService configService,
        HistoryService historyService,
        ContextService contextService,
        GenerationCoordinator coordinator,
        TaskSchedulerService taskSchedulerService,
        UpdateChecker updateChecker,
        IHttpClientFactory httpClientFactory,
        ILogger<MainWindowViewModel> logger)
    {
        _configService = configService;
        _historyService = historyService;
        _contextService = contextService;
        _coordinator = coordinator;
        _taskSchedulerService = taskSchedulerService;
        _updateChecker = updateChecker;
        _httpClientFactory = httpClientFactory;
        _logger = logger;

        ShowUpdateControls = _updateChecker.IsInstalled;
        _updateChecker.UpdateAvailable += UpdateChecker_UpdateAvailable;
        SyncUpdateInfo();
        AppConfig = configService.Load();
        ShowSetupWizard = !configService.HasSavedConfig;
        SelectedSchedule = AppConfig.Schedule;
        foreach (var src in AppConfig.RssSources)
            RssSources.Add(src);
        IsTaskSchedulerEnabled = _taskSchedulerService.IsEnabled();
        if (ShowSetupWizard)
        {
            IsTaskSchedulerEnabled = true;
            LastResultMessage = string.Empty;
        }
        LoadHistory();
        _ = InitializeDataAsync();
    }

    private void UpdateChecker_UpdateAvailable(object? sender, EventArgs e)
    {
        // Avalonia: UIThread.CheckAccess/Invoke で UI スレッドにマーシャリング
        if (Dispatcher.UIThread.CheckAccess())
        {
            SyncUpdateInfo();
            return;
        }

        Dispatcher.UIThread.Invoke(SyncUpdateInfo);
    }

    private void SyncUpdateInfo()
    {
        HasUpdate = _updateChecker.HasUpdate;
        LatestVersion = _updateChecker.LatestVersion;
    }

    /// <summary>起動時にカレンダー一覧・カレンダーイベント・ニュースをバックグラウンドで取得する</summary>
    private async Task InitializeDataAsync()
    {
        var canAccessCalendarSilently = await _contextService.CanAccessCalendarSilentlyAsync();
        if (!canAccessCalendarSilently)
            CalendarStatus = AppResources.CalendarStatusNotConnected;

        if (canAccessCalendarSilently)
        {
            try
            {
                await RefreshCalendarDataAsync(includeFoundSuffix: false);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "起動時のカレンダーデータ取得をスキップしました");
            }
        }

        // ニュース
        try
        {
            await foreach (var n in _contextService.FetchNewsAsync())
                RecentNews.Add(n);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "起動時のニュース取得でエラーが発生しました");
        }
    }

    [RelayCommand(CanExecute = nameof(CanGenerate))]
    private async Task GenerateAsync(CancellationToken ct = default)
    {
        IsGenerating = true;
        LastResultMessage = AppResources.LastResultGenerating;
        GenerateCommand.NotifyCanExecuteChanged();

        try
        {
            var result = await _coordinator.RunAsync(ct: ct);
            LastResultMessage = result.IsSuccess
                ? AppResources.Format(AppResources.LastResultDone, result.AppliedImagePath)
                : AppResources.Format(AppResources.LastResultFailed, result.ErrorSummary);

            if (result.IsSuccess && result.AppliedImagePath != null)
                LastImagePreviewPath = result.AppliedImagePath;

            LoadHistory();
        }
        catch (Exception ex)
        {
            LastResultMessage = AppResources.Format(AppResources.LastResultError, ex.Message);
        }
        finally
        {
            IsGenerating = false;
            GenerateCommand.NotifyCanExecuteChanged();
        }
    }

    private bool CanGenerate() => !IsGenerating;

    private bool CanCheckUpdate() => ShowUpdateControls && !IsCheckingUpdate;

    partial void OnIsGeneratingChanged(bool value)
    {
        GenerateCommand.NotifyCanExecuteChanged();
        CompleteSetupCommand.NotifyCanExecuteChanged();
    }

    partial void OnIsCheckingUpdateChanged(bool value)
    {
        CheckUpdateCommand.NotifyCanExecuteChanged();
    }

    [RelayCommand(CanExecute = nameof(CanCheckUpdate))]
    private async Task CheckUpdateAsync(CancellationToken ct = default)
    {
        IsCheckingUpdate = true;
        try
        {
            await _updateChecker.CheckAsync(ct);
            SyncUpdateInfo();
            LastResultMessage = HasUpdate
                ? AppResources.Format(AppResources.UpdateAvailableMessage, LatestVersion)
                : AppResources.UpdateNotAvailable;
        }
        catch (Exception ex)
        {
            LastResultMessage = AppResources.Format(AppResources.UpdateCheckFailed, ex.Message);
        }
        finally
        {
            IsCheckingUpdate = false;
        }
    }

    [RelayCommand]
    private void InstallUpdate()
    {
        try
        {
            _updateChecker.InstallUpdate();
        }
        catch (Exception ex)
        {
            LastResultMessage = AppResources.Format(AppResources.UpdateInstallStartFailed, ex.Message);
        }
    }

    [RelayCommand]
    private void OpenReleaseNotes()
    {
        try
        {
            _updateChecker.OpenReleaseNotes();
        }
        catch (Exception ex)
        {
            LastResultMessage = AppResources.Format(AppResources.UpdateReleaseNotesOpenFailed, ex.Message);
        }
    }

    [RelayCommand]
    private void Save()
    {
        try
        {
            SaveSettings(IsTaskSchedulerEnabled, AppResources.SettingsSaved);
        }
        catch (Exception ex)
        {
            LastResultMessage = AppResources.Format(AppResources.SettingsSaveError, ex.Message);
        }
    }

    [RelayCommand]
    private void ToggleTaskScheduler()
    {
        try
        {
            if (IsTaskSchedulerEnabled)
                _taskSchedulerService.Enable();
            else
                _taskSchedulerService.Disable();
        }
        catch (Exception ex)
        {
            IsTaskSchedulerEnabled = !IsTaskSchedulerEnabled;
            LastResultMessage = AppResources.Format(AppResources.TaskSchedulerError, ex.Message);
        }
    }

    [RelayCommand(CanExecute = nameof(CanGenerate))]
    private async Task CompleteSetup(CancellationToken ct = default)
    {
        LastResultMessage = string.Empty;
        var setupCompletedMessage = AppResources.SetupCompleted;
        var setupSavedMessage = AppResources.SetupSavedGenerating;

        var apiKey = AppConfig.GoogleAiApiKey.Trim();
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            LastResultMessage = AppResources.SetupApiKeyRequired;
            return;
        }

        AppConfig.GoogleAiApiKey = apiKey;

        var sourceUrl = NewRssSourceUrl.Trim();
        if (!string.IsNullOrEmpty(sourceUrl))
        {
            if (!Uri.TryCreate(sourceUrl, UriKind.Absolute, out _))
            {
                LastResultMessage = AppResources.SetupRssUrlInvalid;
                return;
            }

            var resolvedRssUrl = await ResolveRssSourceUrlAsync(sourceUrl, ct);
            if (resolvedRssUrl is null)
            {
                LastResultMessage = AppResources.SetupNewsSiteRssNotFound;
                return;
            }

            if (!RssSources.Contains(resolvedRssUrl))
                RssSources.Add(resolvedRssUrl);
        }

        if (IsCalendarConnected)
        {
            var primaryCalendar = AvailableCalendars.FirstOrDefault(static c => c.IsPrimary);
            primaryCalendar?.IsSelected = true;
        }

        IsGenerating = true;

        try
        {
            SaveSettings(IsTaskSchedulerEnabled, setupSavedMessage);
            NewRssSourceUrl = string.Empty;

            if (IsCalendarConnected && AvailableCalendars.Count > 0)
            {
                try
                {
                    await RefreshCalendarDataAsync(ct);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "初回セットアップ完了後のカレンダーデータ取得をスキップしました");
                }
            }

            if (RssSources.Count > 0)
            {
                try
                {
                    RecentNews.Clear();
                    await foreach (var n in _contextService.FetchNewsAsync(ct))
                        RecentNews.Add(n);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "初回セットアップ完了後のニュース取得をスキップしました");
                }
            }

            var result = await _coordinator.RunAsync(skipIfNoChanges: false, ct: ct);
            LoadHistory();

            if (result.IsSuccess && result.AppliedImagePath != null)
            {
                LastImagePreviewPath = result.AppliedImagePath;
                LastResultMessage = AppResources.Format(AppResources.SetupCompletedWithImage, setupCompletedMessage, result.AppliedImagePath);
                ShowSetupWizard = false;
                return;
            }

            LastResultMessage = AppResources.Format(
                AppResources.SetupGenerationFailed,
                result.ErrorSummary ?? AppResources.SetupImagePathUnavailable);
        }
        catch (Exception ex) when (IsTaskSchedulerEnabled && ex is SecurityException or UnauthorizedAccessException)
        {
            LastResultMessage = AppResources.Format(AppResources.SetupTaskSchedulerFailed, ex.Message);
        }
        catch (Exception ex)
        {
            LastResultMessage = AppResources.Format(AppResources.SetupFailed, ex.Message);
        }
        finally
        {
            IsGenerating = false;
        }
    }

    [RelayCommand]
    private async Task ConnectCalendarAsync(CancellationToken ct = default)
    {
        CalendarStatus = IsCalendarConnected
            ? AppResources.CalendarStatusRefreshing
            : AppResources.CalendarStatusConnecting;
        try
        {
            _ = await _contextService.GetCalendarServiceInteractiveAsync(ct);
            await RefreshCalendarDataAsync(ct, includeFoundSuffix: true);
        }
        catch (Exception ex)
        {
            CalendarStatus = AppResources.Format(AppResources.CalendarStatusError, ex.Message);
        }
    }

    private async Task RefreshCalendarDataAsync(
        CancellationToken ct = default,
        bool includeFoundSuffix = false)
    {
        var selectedCalendarIds = AvailableCalendars
            .Where(c => c.IsSelected)
            .Select(c => c.Id)
            .ToHashSet(StringComparer.Ordinal);
        if (selectedCalendarIds.Count == 0)
        {
            selectedCalendarIds = AppConfig.TargetCalendarIds
                .ToHashSet(StringComparer.Ordinal);
        }

        var calendars = new List<AvailableCalendar>();

        await foreach (var cal in _contextService.FetchAvailableCalendarsAsync(ct))
            calendars.Add(cal);

        foreach (var cal in calendars)
            cal.IsSelected = selectedCalendarIds.Contains(cal.Id);

        if (selectedCalendarIds.Count > 0)
            AppConfig.TargetCalendarIds = [.. selectedCalendarIds];

        AvailableCalendars.Clear();
        foreach (var cal in calendars)
            AvailableCalendars.Add(cal);

        RecentEvents.Clear();
        await foreach (var ev in _contextService.FetchCalendarEventsAsync(ct))
            RecentEvents.Add(ev);

        IsCalendarConnected = true;
        CalendarStatus = RecentEvents.Count > 0
            ? includeFoundSuffix
                ? AppResources.Format(AppResources.CalendarStatusConnectedEventFound, RecentEvents.Count)
                : AppResources.Format(AppResources.CalendarStatusConnectedEvents, RecentEvents.Count)
            : AppResources.CalendarStatusConnectedNoEvents;
    }

    [RelayCommand]
    private async Task FetchNewsAsync(CancellationToken ct = default)
    {
        try
        {
            RecentNews.Clear();
            await foreach (var n in _contextService.FetchNewsAsync(ct))
                RecentNews.Add(n);
        }
        catch (Exception ex)
        {
            LastResultMessage = AppResources.Format(AppResources.NewsFetchError, ex.Message);
        }
    }

    [RelayCommand]
    private async Task AddRssSource(CancellationToken ct = default)
    {
        var sourceUrl = NewRssSourceUrl.Trim();
        if (string.IsNullOrEmpty(sourceUrl))
            return;

        if (!Uri.TryCreate(sourceUrl, UriKind.Absolute, out _))
        {
            LastResultMessage = AppResources.SetupRssUrlInvalid;
            return;
        }

        var resolvedRssUrl = await ResolveRssSourceUrlAsync(sourceUrl, ct);
        if (resolvedRssUrl is null)
        {
            LastResultMessage = AppResources.SetupNewsSiteRssNotFound;
            return;
        }

        if (RssSources.Contains(resolvedRssUrl))
            return;

        RssSources.Add(resolvedRssUrl);
        NewRssSourceUrl = string.Empty;
        LastResultMessage = string.Empty;
    }

    [RelayCommand]
    private void RemoveRssSource(string? url)
    {
        if (!string.IsNullOrEmpty(url))
            RssSources.Remove(url);
    }

    private async Task<string?> ResolveRssSourceUrlAsync(string sourceUrl, CancellationToken ct)
    {
        var sourceUri = new Uri(sourceUrl, UriKind.Absolute);

        if (IsLikelyRssUrl(sourceUri))
            return sourceUrl;

        var detectedRssUrl = await TryDetectRssUrlFromSiteAsync(sourceUri, ct);
        if (detectedRssUrl is not null)
            return detectedRssUrl;

        return null;
    }

    private async Task<string?> TryDetectRssUrlFromSiteAsync(Uri siteUri, CancellationToken ct)
    {
        var httpClient = _httpClientFactory.CreateClient("WondayWall");
        string content;
        try
        {
            using var response = await httpClient.GetAsync(siteUri, HttpCompletionOption.ResponseHeadersRead, ct);
            response.EnsureSuccessStatusCode();

            if (response.Content.Headers.ContentLength is > MaxSiteHtmlChars)
            {
                _logger.LogDebug("サイトのHTMLサイズが上限を超えたためRSS検出を中止しました [{SiteUrl}]", siteUri);
                return null;
            }

            await using var stream = await response.Content.ReadAsStreamAsync(ct);
            using var reader = new StreamReader(stream);
            content = await ReadToLimitAsync(reader, MaxSiteHtmlChars, ct);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "サイトURLからのHTML取得に失敗しました [{SiteUrl}]", siteUri);
            return null;
        }

        try
        {
            var document = await HtmlParser.ParseDocumentAsync(content, ct);
            foreach (var linkTag in document.QuerySelectorAll("link[rel][type][href]"))
            {
                var relValue = linkTag.GetAttribute("rel");
                if (!ContainsToken(relValue, "alternate"))
                    continue;

                var typeValue = linkTag.GetAttribute("type");
                if (typeValue is null || !IsFeedContentType(typeValue))
                    continue;

                var hrefValue = linkTag.GetAttribute("href");
                if (string.IsNullOrWhiteSpace(hrefValue))
                    continue;

                if (!Uri.TryCreate(siteUri, hrefValue, out var rssUri))
                    continue;

                return rssUri.ToString();
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "サイトURLのHTMLパースに失敗しました [{SiteUrl}]", siteUri);
        }

        return null;
    }

    private static async Task<string> ReadToLimitAsync(TextReader reader, int maxChars, CancellationToken ct)
    {
        var buffer = new char[4_096];
        var content = new StringBuilder(capacity: Math.Min(maxChars, 64_000));
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            var readCount = await reader.ReadAsync(buffer.AsMemory(0, buffer.Length), ct);
            if (readCount <= 0)
                break;

            var writableCount = Math.Min(readCount, maxChars - content.Length);
            if (writableCount > 0)
                content.Append(buffer, 0, writableCount);

            if (content.Length >= maxChars)
                break;
        }

        return content.ToString();
    }

    private static bool ContainsToken(string? source, string token)
    {
        if (string.IsNullOrWhiteSpace(source))
            return false;

        return source
            .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(v => string.Equals(v, token, StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsFeedContentType(string contentType)
    {
        return contentType.Contains("application/rss+xml", StringComparison.OrdinalIgnoreCase)
               || contentType.Contains("application/atom+xml", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsLikelyRssUrl(Uri uri)
    {
        var path = uri.AbsolutePath;
        if (path.EndsWith(".xml", StringComparison.OrdinalIgnoreCase)
            || path.EndsWith(".rss", StringComparison.OrdinalIgnoreCase)
            || path.EndsWith(".atom", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return path.Contains("feed", StringComparison.OrdinalIgnoreCase)
               || path.Contains("rss", StringComparison.OrdinalIgnoreCase)
               || path.Contains("atom", StringComparison.OrdinalIgnoreCase)
               || uri.Query.Contains("feed", StringComparison.OrdinalIgnoreCase)
               || uri.Query.Contains("rss", StringComparison.OrdinalIgnoreCase)
               || uri.Query.Contains("atom", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>選択されているテンプレートの内容をユーザープロンプトに適用する</summary>
    [RelayCommand]
    private void ApplyPromptTemplate()
    {
        if (SelectedPromptTemplate is null)
            return;
        AppConfig.UserPrompt = SelectedPromptTemplate.Content;
        OnPropertyChanged(nameof(AppConfig));
    }

    [RelayCommand]
    private void OpenHistoryImage(HistoryItem? item)
    {
        var imagePath = item?.AppliedImagePath;
        if (string.IsNullOrWhiteSpace(imagePath))
        {
            LastResultMessage = AppResources.HistoryImagePathMissing;
            return;
        }

        if (!File.Exists(imagePath))
        {
            LastResultMessage = AppResources.Format(AppResources.HistoryImageFileNotFound, imagePath);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = imagePath,
                UseShellExecute = true,
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "履歴画像を開けませんでした: {ImagePath}", imagePath);
            LastResultMessage = AppResources.Format(AppResources.HistoryImageOpenFailed, ex.Message);
        }
    }

    [RelayCommand]
    private void OpenLink(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
            return;

        try
        {
            Process.Start(new ProcessStartInfo(url)
            {
                UseShellExecute = true,
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "リンクを開けませんでした: {Url}", url);
            LastResultMessage = AppResources.Format(AppResources.AboutLinkOpenFailed, ex.Message);
        }
    }

    [RelayCommand]
    private void OpenLicensesFolder()
    {
        var licensesPath = Path.Combine(AppContext.BaseDirectory, "licenses");
        if (!Directory.Exists(licensesPath))
        {
            _logger.LogWarning("ライセンスフォルダが見つかりません: {Path}", licensesPath);
            LastResultMessage = AppResources.AboutLicensesFolderNotFound;
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = licensesPath,
                UseShellExecute = true,
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "ライセンスフォルダを開けませんでした: {Path}", licensesPath);
            LastResultMessage = AppResources.Format(AppResources.AboutLicensesFolderOpenFailed, ex.Message);
        }
    }

    private void LoadHistory()
    {
        var items = _historyService.Load();
        History.Clear();
        foreach (var item in items)
            History.Add(item);
    }

    private void SaveSettings(bool enableTaskScheduler, string successMessage)
    {
        ApplyCurrentSelectionsToConfig();
        ApplyTaskSchedulerState(enableTaskScheduler);
        _configService.Save(AppConfig);
        // AppConfig は変更通知を持たないため、ネストされた値を参照するバインディングを再評価させる。
        OnPropertyChanged(nameof(AppConfig));
        IsTaskSchedulerEnabled = enableTaskScheduler;
        LastResultMessage = successMessage;
    }

    private void ApplyCurrentSelectionsToConfig()
    {
        AppConfig.Schedule = SelectedSchedule;
        AppConfig.RssSources = [.. RssSources];
        if (AvailableCalendars.Count > 0)
        {
            AppConfig.TargetCalendarIds = AvailableCalendars
                .Where(c => c.IsSelected)
                .Select(c => c.Id)
                .ToList();
        }
    }

    private void ApplyTaskSchedulerState(bool enableTaskScheduler)
    {
        if (enableTaskScheduler)
            _taskSchedulerService.Enable();
        else
            _taskSchedulerService.Disable();
    }

    partial void OnSelectedScheduleChanged(UpdateSchedule value)
    {
        AppConfig.Schedule = value;
        OnPropertyChanged(nameof(TaskSchedulerScheduleDescription));
    }
}
