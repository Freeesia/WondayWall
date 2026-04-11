using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WondayWall.Models;
using WondayWall.Services;

namespace WondayWall.ViewModels;

public partial class MainWindowViewModel : ObservableObject
{
    private readonly AppConfigService _configService;
    private readonly ContextService _contextService;
    private readonly GenerationCoordinator _coordinator;
    private readonly TaskSchedulerService _taskSchedulerService;

    [ObservableProperty]
    public partial AppConfig AppConfig { get; set; } = new();

    [ObservableProperty]
    public partial string CalendarStatus { get; set; } = "Not connected";

    [ObservableProperty]
    public partial string LastResultMessage { get; set; } = "No generation yet";

    [ObservableProperty]
    public partial bool IsGenerating { get; set; }

    [ObservableProperty]
    public partial bool IsTaskSchedulerEnabled { get; set; }

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

    public MainWindowViewModel(
        AppConfigService configService,
        ContextService contextService,
        GenerationCoordinator coordinator,
        TaskSchedulerService taskSchedulerService)
    {
        _configService = configService;
        _contextService = contextService;
        _coordinator = coordinator;
        _taskSchedulerService = taskSchedulerService;

        AppConfig = configService.Load();
        foreach (var src in AppConfig.RssSources)
            RssSources.Add(src);
        IsTaskSchedulerEnabled = _taskSchedulerService.IsEnabled();
        LoadHistory();
    }

    [RelayCommand(CanExecute = nameof(CanGenerate))]
    private async Task GenerateAsync(CancellationToken ct = default)
    {
        IsGenerating = true;
        LastResultMessage = "Generating...";
        GenerateCommand.NotifyCanExecuteChanged();

        try
        {
            var result = await _coordinator.RunAsync(ct);
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
        AppConfig.RssSources = [.. RssSources];
        if (AvailableCalendars.Count > 0)
        {
            AppConfig.TargetCalendarIds = AvailableCalendars
                .Where(c => c.IsSelected)
                .Select(c => c.Id)
                .ToList();
        }
        _configService.Save(AppConfig);
        if (IsTaskSchedulerEnabled)
            _taskSchedulerService.Enable();
        LastResultMessage = "Settings saved.";
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
    private async Task CheckConnectionAsync(CancellationToken ct = default)
    {
        CalendarStatus = "Checking...";
        try
        {
            var events = await _contextService.FetchCalendarEventsAsync(ct);
            RecentEvents.Clear();
            foreach (var ev in events)
                RecentEvents.Add(ev);

            CalendarStatus = events.Count > 0
                ? $"Connected — {events.Count} event(s) found"
                : "Connected — no upcoming events";
        }
        catch (Exception ex)
        {
            CalendarStatus = $"Error: {ex.Message}";
        }
    }

    [RelayCommand]
    private async Task FetchAvailableCalendarsAsync(CancellationToken ct = default)
    {
        CalendarStatus = "Fetching calendar list...";
        try
        {
            var calendars = await _contextService.FetchAvailableCalendarsAsync(ct);
            AvailableCalendars.Clear();
            foreach (var cal in calendars)
            {
                cal.IsSelected = AppConfig.TargetCalendarIds.Contains(cal.Id);
                AvailableCalendars.Add(cal);
            }
            CalendarStatus = calendars.Count > 0
                ? $"Calendar list: {calendars.Count} item(s)"
                : "No calendars found";
        }
        catch (Exception ex)
        {
            CalendarStatus = $"Error: {ex.Message}";
        }
    }

    [RelayCommand]
    private async Task FetchNewsAsync(CancellationToken ct = default)
    {
        try
        {
            var news = await _contextService.FetchNewsAsync(ct);
            RecentNews.Clear();
            foreach (var n in news)
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

    private void LoadHistory()
    {
        var items = _coordinator.LoadHistory();
        History.Clear();
        foreach (var item in items)
            History.Add(item);
    }
}
