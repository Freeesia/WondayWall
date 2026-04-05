using System;
using System.Linq;
using System.Threading.Tasks;
using ConsoleAppFramework;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Wpf.Extensions.Hosting;
using WondayWall.Commands;
using WondayWall.Services;
using WondayWall.ViewModels;
using WondayWall.Views;

namespace WondayWall;

internal static class Program
{
    private static readonly string[] CliCommandNames =
        ["run-once", "generate", "check-calendar", "check-news", "check-google-ai"];

    [STAThread]
    public static async Task Main(string[] args)
    {
        bool isCli = args.Length > 0 &&
            CliCommandNames.Contains(args[0], StringComparer.OrdinalIgnoreCase);

        if (isCli)
        {
            await RunCliAsync(args);
        }
        else
        {
            await RunGuiAsync(args);
        }
    }

    private static async Task RunCliAsync(string[] args)
    {
        var app = ConsoleApp.Create()
            .ConfigureServices(services =>
            {
                services.AddSingleton<AppConfigService>();
                services.AddSingleton<ContextService>();
                services.AddSingleton<GoogleAiService>();
                services.AddSingleton<WallpaperService>();
                services.AddSingleton<GenerationCoordinator>();
            });

        app.Add<CliCommands>();
        await app.RunAsync(args);
    }

    private static async Task RunGuiAsync(string[] args)
    {
        var builder = WpfApplication<App, MainWindow>.CreateBuilder(args);

        builder.Services.AddSingleton<AppConfigService>();
        builder.Services.AddSingleton<ContextService>();
        builder.Services.AddSingleton<GoogleAiService>();
        builder.Services.AddSingleton<WallpaperService>();
        builder.Services.AddSingleton<GenerationCoordinator>();
        builder.Services.AddTransient<MainWindowViewModel>();
        builder.Services.AddTransient<MainWindow>();

        var wpfApp = builder.Build();
        await wpfApp.RunAsync();
    }
}
