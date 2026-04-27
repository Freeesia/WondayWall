using Microsoft.Win32.TaskScheduler;
using System.Security.Principal;
using WondayWall.Utils;

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
        td.RegistrationInfo.Description =
            $"WondayWall の定期壁紙更新タスクです ({ScheduleHelper.FormatSlotTimes(runsPerDay)} + ログオン時補完)。バックグラウンド実行用のため Google AI の画像生成を Flex モードで実行し、Flex が失敗した場合は Standard にフォールバックします。実行時点の予定・ニュースを取得してから画像生成し、完了後に壁紙へ適用します。";

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

        using var identity = WindowsIdentity.GetCurrent();
        var logonTrigger = new LogonTrigger
        {
            UserId = identity.Name,
            Enabled = true,
        };

        td.Triggers.Add(dailyTrigger);
        td.Triggers.Add(logonTrigger);
        td.Settings.MultipleInstances = TaskInstancesPolicy.IgnoreNew;
        td.Settings.StartWhenAvailable = false;

        td.Actions.Add(new ExecAction(Environment.ProcessPath, "run-once"));

        ts.RootFolder.RegisterTaskDefinition(TaskName, td);
    }

    public void Disable()
    {
        using var ts = new TaskService();
        ts.RootFolder.DeleteTask(TaskName, exceptionOnNotExists: false);
    }
}
