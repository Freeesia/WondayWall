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

    [ObservableProperty]
    private AppConfig _appConfig = new();

    [ObservableProperty]
    private string _calendarStatus = "Not connected";

    [ObservableProperty]
    private string _lastResultMessage = "No generation yet";

    [ObservableProperty]
    private bool _isGenerating;

    [ObservableProperty]
    private GeneratedImageInfo? _lastGeneratedImage;

    [ObservableProperty]
    private string _lastImagePreviewPath = string.Empty;

    public ObservableCollection<CalendarEventItem> RecentEvents { get; } = [];
    public ObservableCollection<NewsTopicItem> RecentNews { get; } = [];
    public ObservableCollection<HistoryItem> History { get; } = [];

    public MainWindowViewModel(
        AppConfigService configService,
        ContextService contextService,
        GenerationCoordinator coordinator)
    {
        _configService = configService;
        _contextService = contextService;
        _coordinator = coordinator;

        AppConfig = configService.Load();
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
        _configService.Save(AppConfig);
        LastResultMessage = "Settings saved.";
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

    private void LoadHistory()
    {
        var items = _coordinator.LoadHistory();
        History.Clear();
        foreach (var item in items)
            History.Add(item);
    }
}
