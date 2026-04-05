using ConsoleAppFramework;
using Kamishibai;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using WondayWall;
using WondayWall.Commands;
using WondayWall.Services;
using WondayWall.ViewModels;
using WondayWall.Views;
using Wpf.Extensions.Hosting;

// Thread.CurrentThread.SetApartmentState(ApartmentState.STA);

var cafApp = ConsoleApp.Create()
    .ConfigureServices(ConfigureCommonServices);

cafApp.Add<CliCommands>();
cafApp.Add("", () =>
{
    var builder = WpfApplication<App, MainWindow>.CreateBuilder(args);
    ConfigureCommonServices(builder.Services);
    builder.Services.AddPresentation<MainWindow, MainWindowViewModel>();
    var wpfApp = builder.Build();
    return wpfApp.RunAsync();
});

await cafApp.RunAsync(args).ConfigureAwait(false);

static void ConfigureCommonServices(IServiceCollection services)
{
    services.AddSingleton<AppConfigService>();
    services.AddSingleton<ContextService>();
    services.AddSingleton<GoogleAiService>();
    services.AddSingleton<WallpaperService>();
    services.AddSingleton<GenerationCoordinator>();
    services.AddSingleton<TaskSchedulerService>();
}
