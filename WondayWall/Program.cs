using System.Net.Http;
using ConsoleAppFramework;
using Kamishibai;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using WondayWall;
using WondayWall.Commands;
using WondayWall.Services;
using WondayWall.ViewModels;
using WondayWall.Views;

var cafApp = ConsoleApp.Create()
    .ConfigureServices(ConfigureCommonServices);

cafApp.Add<CliCommands>();
cafApp.Add("", async () =>
{
    var builder = KamishibaiApplication<App, MainWindow>.CreateBuilder();
    ConfigureCommonServices(builder.Services);
    builder.Services
        .AddPresentation<MainWindow, MainWindowViewModel>();
    var wpfApp = builder.Build();
    await wpfApp.RunAsync();
});

await cafApp.RunAsync(args).ConfigureAwait(false);

static void ConfigureCommonServices(IServiceCollection services)
{
    services.AddLogging(b => b.AddConsole());
    services.AddSingleton<HttpClient>(_ => new HttpClient { Timeout = TimeSpan.FromSeconds(30) });
    services.AddSingleton<WallpaperService>();
    services.AddSingleton<AppConfigService>();
    services.AddSingleton<ContextService>();
    services.AddSingleton<GoogleAiService>();
    services.AddSingleton<GenerationCoordinator>();
    services.AddSingleton<TaskSchedulerService>();
}
