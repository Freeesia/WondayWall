using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Security;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Services;
using WondayWall.Utils;

namespace WondayWall.ViewModels;

public partial class MainWindowViewModel : ObservableObject
{
    private readonly AppConfigService _configService;
    private readonly ContextService _contextService;
    private readonly GenerationCoordinator _coordinator;
    private readonly TaskSchedulerService _taskSchedulerService;
    private readonly ILogger<MainWindowViewModel> _logger;

    [ObservableProperty]
    public partial AppConfig AppConfig { get; set; } = new();

    [ObservableProperty]
    public partial string CalendarStatus { get; set; } = "Not connected";

    [ObservableProperty]
    public partial bool IsCalendarConnected { get; set; }

    [ObservableProperty]
    public partial string LastResultMessage { get; set; } = "No generation yet";

    [ObservableProperty]
    public partial bool IsGenerating { get; set; }

    [ObservableProperty]
    public partial bool IsTaskSchedulerEnabled { get; set; }

    [ObservableProperty]
    public partial bool ShowSetupWizard { get; set; }

    [ObservableProperty]
    public partial int SelectedRunsPerDay { get; set; }

    [ObservableProperty]
    public partial GeneratedImageInfo? LastGeneratedImage { get; set; }

    [ObservableProperty]
    public partial string LastImagePreviewPath { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string NewRssSourceUrl { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string? SelectedRssSource { get; set; }
    public ObservableCollection<CalendarEventItem> RecentEvents { get; } = [];
    public ObservableCollection<NewsTopicItem> RecentNews { get; } = [];
    public ObservableCollection<HistoryItem> History { get; } = [];
    public ObservableCollection<string> RssSources { get; } = [];
    public ObservableCollection<AvailableCalendar> AvailableCalendars { get; } = [];
    public IReadOnlyList<int> AvailableRunsPerDayOptions => ScheduleHelper.SupportedRunsPerDay;
    public string TaskSchedulerScheduleDescription => ScheduleHelper.FormatScheduleDescription(SelectedRunsPerDay);

    public MainWindowViewModel(
        AppConfigService configService,
        ContextService contextService,
        GenerationCoordinator coordinator,
        TaskSchedulerService taskSchedulerService,
        ILogger<MainWindowViewModel> logger)
    {
        _configService = configService;
        _contextService = contextService;
        _coordinator = coordinator;
        _taskSchedulerService = taskSchedulerService;
        _logger = logger;

        AppConfig = configService.Load();
        ShowSetupWizard = !configService.HasSavedConfig;
        SelectedRunsPerDay = ScheduleHelper.NormalizeRunsPerDay(AppConfig.RunsPerDay);
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

    /// <summary>起動時にカレンダー一覧・カレンダーイベント・ニュースをバックグラウンドで取得する</summary>
    private async Task InitializeDataAsync()
    {
        var canAccessCalendarSilently = await _contextService.CanAccessCalendarSilentlyAsync();
        if (!canAccessCalendarSilently)
            CalendarStatus = "Not connected";

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
        LastResultMessage = "Generating...";
        GenerateCommand.NotifyCanExecuteChanged();

        try
        {
            var result = await _coordinator.RunAsync(ct: ct);
            LastResultMessage = result.IsSuccess
                ? $"Done! Image: {result.AppliedImagePath}"
                : $"Failed: {result.ErrorSummary}";

            if (result.IsSuccess && result.AppliedImagePath != null)
                LastImagePreviewPath = result.AppliedImagePath;

            LoadHistory();
        }
        catch (Exception ex)
        {
            LastResultMessage = $"Error: {ex.Message}";
        }
        finally
        {
            IsGenerating = false;
            GenerateCommand.NotifyCanExecuteChanged();
        }
    }

    private bool CanGenerate() => !IsGenerating;

    [RelayCommand]
    private void Save()
    {
        try
        {
            SaveSettings(IsTaskSchedulerEnabled, "Settings saved.");
        }
        catch (Exception ex)
        {
            LastResultMessage = $"Settings save error: {ex.Message}";
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
            LastResultMessage = $"Task Scheduler error: {ex.Message}";
        }
    }

    [RelayCommand]
    private async Task CompleteSetup(CancellationToken ct = default)
    {
        LastResultMessage = string.Empty;
        const string setupCompletedMessage = "初回セットアップが完了しました。";

        var apiKey = AppConfig.GoogleAiApiKey.Trim();
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            LastResultMessage = "Google AI APIキーを入力してください。";
            return;
        }

        AppConfig.GoogleAiApiKey = apiKey;

        var rssUrl = NewRssSourceUrl.Trim();
        if (!string.IsNullOrEmpty(rssUrl))
        {
            if (!Uri.TryCreate(rssUrl, UriKind.Absolute, out _))
            {
                LastResultMessage = "有効なRSSフィードURLを入力してください。";
                return;
            }

            RssSources.Add(rssUrl);
        }

        if (IsCalendarConnected)
        {
            var primaryCalendar = AvailableCalendars.FirstOrDefault(static c => c.IsPrimary);
            primaryCalendar?.IsSelected = true;
        }

        try
        {
            SaveSettings(IsTaskSchedulerEnabled, setupCompletedMessage);
            ShowSetupWizard = false;
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

            LastResultMessage = setupCompletedMessage;
        }
        catch (Exception ex) when (IsTaskSchedulerEnabled && ex is SecurityException or UnauthorizedAccessException)
        {
            LastResultMessage = $"タスクスケジューラの設定に失敗しました。無効にして完了するか、再試行してください: {ex.Message}";
        }
        catch (Exception ex)
        {
            LastResultMessage = $"初回セットアップを完了できませんでした: {ex.Message}";
        }
    }

    [RelayCommand]
    private async Task ConnectCalendarAsync(CancellationToken ct = default)
    {
        CalendarStatus = IsCalendarConnected ? "再取得中..." : "接続中...";
        try
        {
            _ = await _contextService.GetCalendarServiceInteractiveAsync(ct);
            await RefreshCalendarDataAsync(ct, includeFoundSuffix: true);
        }
        catch (Exception ex)
        {
            CalendarStatus = $"Error: {ex.Message}";
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
                ? $"Connected — {RecentEvents.Count} event(s) found"
                : $"Connected — {RecentEvents.Count} event(s)"
            : "Connected — no upcoming events";
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
            LastResultMessage = $"News fetch error: {ex.Message}";
        }
    }

    [RelayCommand]
    private void AddRssSource()
    {
        var url = NewRssSourceUrl.Trim();
        if (!string.IsNullOrEmpty(url)
            && Uri.TryCreate(url, UriKind.Absolute, out _)
            && !RssSources.Contains(url))
        {
            RssSources.Add(url);
            NewRssSourceUrl = string.Empty;
        }
    }

    [RelayCommand]
    private void RemoveRssSource(string? url)
    {
        if (!string.IsNullOrEmpty(url))
            RssSources.Remove(url);
    }

    [RelayCommand]
    private void OpenHistoryImage(HistoryItem? item)
    {
        var imagePath = item?.AppliedImagePath;
        if (string.IsNullOrWhiteSpace(imagePath))
        {
            LastResultMessage = "画像パスがありません。";
            return;
        }

        if (!File.Exists(imagePath))
        {
            LastResultMessage = $"画像ファイルが見つかりません: {imagePath}";
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
            LastResultMessage = $"画像を開けませんでした: {ex.Message}";
        }
    }

    private void LoadHistory()
    {
        var items = _coordinator.LoadHistory();
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
        AppConfig.RunsPerDay = ScheduleHelper.NormalizeRunsPerDay(SelectedRunsPerDay);
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

    partial void OnSelectedRunsPerDayChanged(int value)
    {
        var normalizedRunsPerDay = ScheduleHelper.NormalizeRunsPerDay(value);
        if (value != normalizedRunsPerDay)
        {
            SelectedRunsPerDay = normalizedRunsPerDay;
            return;
        }

        AppConfig.RunsPerDay = normalizedRunsPerDay;
        OnPropertyChanged(nameof(TaskSchedulerScheduleDescription));
    }
}
