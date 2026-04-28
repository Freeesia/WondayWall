using System.CodeDom.Compiler;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Resources;
using System.Runtime.CompilerServices;

#nullable enable

namespace WondayWall.Properties;

[GeneratedCode("System.Resources.Tools.StronglyTypedResourceBuilder", "17.0.0.0")]
[DebuggerNonUserCode]
[CompilerGenerated]
public static class Resources
{
    private static readonly ResourceManager ResourceManagerInstance =
        new("WondayWall.Properties.Resources", typeof(Resources).Assembly);

    private static CultureInfo? resourceCulture;

    [EditorBrowsable(EditorBrowsableState.Advanced)]
    public static ResourceManager ResourceManager => ResourceManagerInstance;

    [EditorBrowsable(EditorBrowsableState.Advanced)]
    public static CultureInfo? Culture
    {
        get => resourceCulture;
        set => resourceCulture = value;
    }

    public static string Format(string format, params object?[] args)
        => string.Format(resourceCulture ?? CultureInfo.CurrentUICulture, format, args);

    private static string GetString(string name)
        => ResourceManager.GetString(name, resourceCulture)!;

    public static string Add => GetString(nameof(Add));
    public static string AutomaticExecution => GetString(nameof(AutomaticExecution));
    public static string CalendarNotConnected => GetString(nameof(CalendarNotConnected));
    public static string CalendarStatusConnecting => GetString(nameof(CalendarStatusConnecting));
    public static string CalendarStatusConnectedEventFound => GetString(nameof(CalendarStatusConnectedEventFound));
    public static string CalendarStatusConnectedEvents => GetString(nameof(CalendarStatusConnectedEvents));
    public static string CalendarStatusConnectedNoEvents => GetString(nameof(CalendarStatusConnectedNoEvents));
    public static string CalendarStatusError => GetString(nameof(CalendarStatusError));
    public static string CalendarStatusNotConnected => GetString(nameof(CalendarStatusNotConnected));
    public static string CalendarStatusRefreshing => GetString(nameof(CalendarStatusRefreshing));
    public static string CalendarTokenExpired => GetString(nameof(CalendarTokenExpired));
    public static string Connect => GetString(nameof(Connect));
    public static string CurrentWallpaper => GetString(nameof(CurrentWallpaper));
    public static string DataTab => GetString(nameof(DataTab));
    public static string EnableFixedSchedule => GetString(nameof(EnableFixedSchedule));
    public static string EventLocation => GetString(nameof(EventLocation));
    public static string EventStartTime => GetString(nameof(EventStartTime));
    public static string EventTitle => GetString(nameof(EventTitle));
    public static string FetchNewsToolTip => GetString(nameof(FetchNewsToolTip));
    public static string GenerateNow => GetString(nameof(GenerateNow));
    public static string GoogleAiApiKey => GetString(nameof(GoogleAiApiKey));
    public static string GoogleAiBillingError => GetString(nameof(GoogleAiBillingError));
    public static string GoogleAiSettings => GetString(nameof(GoogleAiSettings));
    public static string GoogleCalendar => GetString(nameof(GoogleCalendar));
    public static string HistoryAi => GetString(nameof(HistoryAi));
    public static string HistoryCalendar => GetString(nameof(HistoryCalendar));
    public static string HistoryExecutedAt => GetString(nameof(HistoryExecutedAt));
    public static string HistoryImageFileNotFound => GetString(nameof(HistoryImageFileNotFound));
    public static string HistoryImageOpenFailed => GetString(nameof(HistoryImageOpenFailed));
    public static string HistoryImagePathMissing => GetString(nameof(HistoryImagePathMissing));
    public static string HistoryMessage => GetString(nameof(HistoryMessage));
    public static string HistoryNews => GetString(nameof(HistoryNews));
    public static string HistorySuccess => GetString(nameof(HistorySuccess));
    public static string HomeTab => GetString(nameof(HomeTab));
    public static string LastResult => GetString(nameof(LastResult));
    public static string LastResultDone => GetString(nameof(LastResultDone));
    public static string LastResultError => GetString(nameof(LastResultError));
    public static string LastResultFailed => GetString(nameof(LastResultFailed));
    public static string LastResultGenerating => GetString(nameof(LastResultGenerating));
    public static string LastResultNoGeneration => GetString(nameof(LastResultNoGeneration));
    public static string LatestNewsTopics => GetString(nameof(LatestNewsTopics));
    public static string News => GetString(nameof(News));
    public static string NewsFetchError => GetString(nameof(NewsFetchError));
    public static string OpenApiKeyPage => GetString(nameof(OpenApiKeyPage));
    public static string PublishedAt => GetString(nameof(PublishedAt));
    public static string RecentCalendarEvents => GetString(nameof(RecentCalendarEvents));
    public static string ReferencedCalendars => GetString(nameof(ReferencedCalendars));
    public static string Refresh => GetString(nameof(Refresh));
    public static string RemoveSelected => GetString(nameof(RemoveSelected));
    public static string RssSources => GetString(nameof(RssSources));
    public static string RunsPerDay => GetString(nameof(RunsPerDay));
    public static string RunsPerDayOptionFormat => GetString(nameof(RunsPerDayOptionFormat));
    public static string RunHistory => GetString(nameof(RunHistory));
    public static string SaveSettings => GetString(nameof(SaveSettings));
    public static string ScheduleDescription => GetString(nameof(ScheduleDescription));
    public static string ScheduleSettings => GetString(nameof(ScheduleSettings));
    public static string SettingsSaveError => GetString(nameof(SettingsSaveError));
    public static string SettingsSaved => GetString(nameof(SettingsSaved));
    public static string SettingsTab => GetString(nameof(SettingsTab));
    public static string SetupApiKeyDescription => GetString(nameof(SetupApiKeyDescription));
    public static string SetupApiKeyRequired => GetString(nameof(SetupApiKeyRequired));
    public static string SetupAutomaticExecutionDescription => GetString(nameof(SetupAutomaticExecutionDescription));
    public static string SetupCalendarDescription => GetString(nameof(SetupCalendarDescription));
    public static string SetupCompleted => GetString(nameof(SetupCompleted));
    public static string SetupCompletedWithImage => GetString(nameof(SetupCompletedWithImage));
    public static string SetupDailyTaskDescription => GetString(nameof(SetupDailyTaskDescription));
    public static string SetupDescription => GetString(nameof(SetupDescription));
    public static string SetupEnableDailyTask => GetString(nameof(SetupEnableDailyTask));
    public static string SetupFailed => GetString(nameof(SetupFailed));
    public static string SetupFooterDescription => GetString(nameof(SetupFooterDescription));
    public static string SetupGenerateAndStart => GetString(nameof(SetupGenerateAndStart));
    public static string SetupGenerationFailed => GetString(nameof(SetupGenerationFailed));
    public static string SetupImagePathUnavailable => GetString(nameof(SetupImagePathUnavailable));
    public static string SetupNewsDescription => GetString(nameof(SetupNewsDescription));
    public static string SetupRssUrlInvalid => GetString(nameof(SetupRssUrlInvalid));
    public static string SetupSavedGenerating => GetString(nameof(SetupSavedGenerating));
    public static string SetupStepApiKey => GetString(nameof(SetupStepApiKey));
    public static string SetupStepAutomaticExecution => GetString(nameof(SetupStepAutomaticExecution));
    public static string SetupStepGoogleCalendar => GetString(nameof(SetupStepGoogleCalendar));
    public static string SetupStepNewsSite => GetString(nameof(SetupStepNewsSite));
    public static string SetupTaskSchedulerFailed => GetString(nameof(SetupTaskSchedulerFailed));
    public static string SetupTitle => GetString(nameof(SetupTitle));
    public static string SkipWhenNoChanges => GetString(nameof(SkipWhenNoChanges));
    public static string SkipWhenNoChangesHeader => GetString(nameof(SkipWhenNoChangesHeader));
    public static string TaskSchedulerDescription => GetString(nameof(TaskSchedulerDescription));
    public static string TaskSchedulerError => GetString(nameof(TaskSchedulerError));
    public static string UpdateLockScreen => GetString(nameof(UpdateLockScreen));
    public static string UpdateLockScreenHeader => GetString(nameof(UpdateLockScreenHeader));
    public static string UseCurrentWallpaperAsBase => GetString(nameof(UseCurrentWallpaperAsBase));
    public static string UseCurrentWallpaperAsBaseHeader => GetString(nameof(UseCurrentWallpaperAsBaseHeader));
    public static string UserPromptHeader => GetString(nameof(UserPromptHeader));
}
