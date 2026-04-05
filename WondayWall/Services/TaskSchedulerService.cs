using System.Diagnostics;
using Microsoft.Win32.TaskScheduler;

namespace WondayWall.Services;

public class TaskSchedulerService(AppConfigService configService)
{
    private const string TaskName = "WondayWall";

    public bool IsEnabled()
    {
        using var ts = new TaskService();
        return ts.GetTask(TaskName) is not null;
    }

    public void Enable()
    {
        var config = configService.Load();
        using var ts = new TaskService();
        var td = ts.NewTask();
        td.RegistrationInfo.Description = "WondayWall 壁紙自動生成";

        var trigger = new TimeTrigger
        {
            StartBoundary = DateTime.Now,
            Repetition =
            {
                Interval = TimeSpan.FromHours(config.UpdateIntervalHours),
                Duration = TimeSpan.Zero,
            },
        };
        td.Triggers.Add(trigger);

        var exePath = Process.GetCurrentProcess().MainModule!.FileName;
        td.Actions.Add(new ExecAction(exePath, "run-once"));

        ts.RootFolder.RegisterTaskDefinition(TaskName, td);
    }

    public void Disable()
    {
        using var ts = new TaskService();
        ts.RootFolder.DeleteTask(TaskName, exceptionOnNotExists: false);
    }
}
