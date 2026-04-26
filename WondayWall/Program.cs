using Avalonia;
using ConsoleAppFramework;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Windows.Win32;
using WondayWall;
using WondayWall.Commands;
using WondayWall.Services;
using WondayWall.ViewModels;
using WondayWall.Views;

// STAスレッドを設定
Thread.CurrentThread.SetApartmentState(ApartmentState.Unknown);
Thread.CurrentThread.SetApartmentState(ApartmentState.STA);

if (args is [])
{
    // GUIモード: Generic Host でサービスを構築し Avalonia を起動
    var builder = Host.CreateApplicationBuilder();
    ConfigureCommonServices(builder.Services);
    builder.Services.AddTransient<MainWindow>();
    builder.Services.AddTransient<MainWindowViewModel>();

    using var host = builder.Build();

    AppBuilder.Configure(() => new App(host.Services))
        .UsePlatformDetect()
        .LogToTrace()
        .StartWithClassicDesktopLifetime(args);
}
else
{
    // CLIモード: ConsoleAppFramework
    if (!PInvoke.AttachConsole(PInvoke.ATTACH_PARENT_PROCESS))
    {
#if DEBUG // デバッグビルドの場合はログ見たいのでコンソールを割り当てる
        PInvoke.AllocConsole();
#endif
    }

    var cafApp = ConsoleApp.Create()
        .ConfigureServices(ConfigureCommonServices);

    cafApp.Add<CliCommands>();

    await cafApp.RunAsync(args).ConfigureAwait(false);
}

static void ConfigureCommonServices(IServiceCollection services)
{
    services.AddLogging(b => b.AddConsole());
    services.AddHttpClient("WondayWall", c => c.Timeout = TimeSpan.FromSeconds(30));
    services.AddSingleton<WallpaperService>();
    services.AddSingleton<AppConfigService>();
    services.AddSingleton<HistoryService>();
    services.AddSingleton<ContextService>();
    services.AddSingleton<GoogleAiService>();
    services.AddSingleton<GenerationCoordinator>();
    services.AddSingleton<TaskSchedulerService>();
}
