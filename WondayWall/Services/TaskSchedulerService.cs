using Microsoft.Win32.TaskScheduler;
using System.Security.Principal;

namespace WondayWall.Services;

public class TaskSchedulerService
{
    private const string TaskName = "WondayWall";

    public bool IsEnabled()
    {
        using var ts = new TaskService();
        return ts.GetTask(TaskName) is not null;
    }

    public void Enable()
    {
        using var ts = new TaskService();
        var td = ts.NewTask();
        td.RegistrationInfo.Description = "WondayWall 壁紙自動生成 (0:00 / 6:00 / 12:00 / 18:00 + ログオン時補完)";

        var dailyTrigger = new DailyTrigger
        {
            StartBoundary = DateTime.Today,
            DaysInterval = 1,
        };
        dailyTrigger.Repetition.Interval = TimeSpan.FromHours(6);
        dailyTrigger.Repetition.Duration = TimeSpan.FromDays(1);

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
