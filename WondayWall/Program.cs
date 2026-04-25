using ConsoleAppFramework;
using Kamishibai;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Windows.Win32;
using WondayWall;
using WondayWall.Commands;
using WondayWall.Services;
using WondayWall.ViewModels;
using WondayWall.Views;

// Set STAThread 
Thread.CurrentThread.SetApartmentState(ApartmentState.Unknown);
Thread.CurrentThread.SetApartmentState(ApartmentState.STA);


if (args is [])
{
    var builder = KamishibaiApplication<App, MainWindow>.CreateBuilder();
    ConfigureCommonServices(builder.Services);
    builder.Services
        .AddPresentation<MainWindow, MainWindowViewModel>();
    var wpfApp = builder.Build();
    await wpfApp.RunAsync();
}
else
{
    if (!PInvoke.AttachConsole(PInvoke.ATTACH_PARENT_PROCESS))
    {
        PInvoke.AllocConsole();
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
    services.AddHttpClient("Gemini", c => c.Timeout = TimeSpan.FromMinutes(10));
    services.AddSingleton<WallpaperService>();
    services.AddSingleton<AppConfigService>();
    services.AddSingleton<HistoryService>();
    services.AddSingleton<ContextService>();
    services.AddSingleton<GoogleAiService>();
    services.AddSingleton<GenerationCoordinator>();
    services.AddSingleton<TaskSchedulerService>();
}
