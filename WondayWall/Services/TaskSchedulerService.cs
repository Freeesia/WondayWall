using Microsoft.Win32.TaskScheduler;
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
        var runsPerDay = ScheduleHelper.NormalizeRunsPerDay(appConfigService.Current.RunsPerDay);

        using var ts = new TaskService();
        var td = ts.NewTask();
        td.RegistrationInfo.Description = AppResources.Format(
            AppResources.TaskSchedulerDescription,
            ScheduleHelper.FormatSlotTimes(runsPerDay));

        var dailyTrigger = new DailyTrigger
        {
            StartBoundary = DateTime.Today,
            DaysInterval = 1,
        };
        if (runsPerDay > 1)
        {
            dailyTrigger.Repetition.Interval = ScheduleHelper.GetInterval(runsPerDay);
            dailyTrigger.Repetition.Duration = TimeSpan.FromDays(1);
        }
        td.Triggers.Add(dailyTrigger);

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
}
