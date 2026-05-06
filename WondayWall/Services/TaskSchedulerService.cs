using Microsoft.Win32.TaskScheduler;
using WondayWall.Models;
using WondayWall.Utils;
using AppResources = WondayWall.Properties.Resources;

namespace WondayWall.Services;

public class TaskSchedulerService(AppConfigService appConfigService)
{
    private const string TaskName = "WondayWall";

    public bool IsEnabled()
    {
        using var ts = new TaskService();
        return ts.GetTask(TaskName) is not null;
    }

    public void Enable()
    {
        var schedule = appConfigService.Current.Schedule;
        var slotTimesStr = string.Join(
            " / ",
            ScheduleHelper.GetSlotOffsets(schedule)
                .Select(static offset => $"{(int)offset.TotalHours}:00"));

        using var ts = new TaskService();
        var td = ts.NewTask();
        td.RegistrationInfo.Description = AppResources.Format(
            AppResources.TaskSchedulerDescription,
            slotTimesStr);

        if (ScheduleHelper.IsWeeklySchedule(schedule))
        {
            // 週次トリガー：対象曜日の WeeklySlotTime に実行
            var daysFlags = GetDaysOfTheWeek(ScheduleHelper.GetWeekDays(schedule));
            var weeklyTrigger = new WeeklyTrigger
            {
                StartBoundary = DateTime.Today.Date + ScheduleHelper.WeeklySlotTime,
                WeeksInterval = 1,
                DaysOfWeek = daysFlags,
            };
            td.Triggers.Add(weeklyTrigger);
        }
        else
        {
            // 日次トリガー
            var slots = ScheduleHelper.GetSlotOffsets(schedule);
            var dailyTrigger = new DailyTrigger
            {
                StartBoundary = DateTime.Today.Date + slots[0],
                DaysInterval = 1,
            };
            if (slots.Count > 1)
            {
                dailyTrigger.Repetition.Interval = slots[1] - slots[0];
                dailyTrigger.Repetition.Duration = TimeSpan.FromDays(1);
            }
            td.Triggers.Add(dailyTrigger);
        }

        td.Settings.AllowDemandStart = true;
        td.Settings.DisallowStartIfOnBatteries = false;
        td.Settings.StopIfGoingOnBatteries = false;
        td.Settings.RunOnlyIfNetworkAvailable = false;
        td.Settings.MultipleInstances = TaskInstancesPolicy.IgnoreNew;
        td.Settings.StartWhenAvailable = true;
        td.Settings.RestartInterval = TimeSpan.FromMinutes(5);
        td.Settings.RestartCount = 3;
        td.Settings.ExecutionTimeLimit = TimeSpan.FromHours(12);
        td.Settings.AllowHardTerminate = true;

        td.Actions.Add(new ExecAction(Environment.ProcessPath, "run-once"));

        ts.RootFolder.RegisterTaskDefinition(TaskName, td);
    }

    public void Disable()
    {
        using var ts = new TaskService();
        ts.RootFolder.DeleteTask(TaskName, exceptionOnNotExists: false);
    }

    /// <summary>.NET の DayOfWeek 一覧を TaskScheduler の DaysOfTheWeek に変換する</summary>
    private static DaysOfTheWeek GetDaysOfTheWeek(IReadOnlyList<DayOfWeek> days)
    {
        var flags = default(DaysOfTheWeek);
        foreach (var day in days)
        {
            flags |= day switch
            {
                DayOfWeek.Sunday => DaysOfTheWeek.Sunday,
                DayOfWeek.Monday => DaysOfTheWeek.Monday,
                DayOfWeek.Tuesday => DaysOfTheWeek.Tuesday,
                DayOfWeek.Wednesday => DaysOfTheWeek.Wednesday,
                DayOfWeek.Thursday => DaysOfTheWeek.Thursday,
                DayOfWeek.Friday => DaysOfTheWeek.Friday,
                DayOfWeek.Saturday => DaysOfTheWeek.Saturday,
                _ => default,
            };
        }
        return flags;
    }
}
