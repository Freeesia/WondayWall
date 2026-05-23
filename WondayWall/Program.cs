using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using ConsoleAppFramework;
using System.IO;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http.Resilience;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Octokit;
using Polly;
using Windows.Win32;
using WondayWall;
using WondayWall.Commands;
using WondayWall.Services;
using WondayWall.ViewModels;
using WondayWall.Views;

// Set STAThread 
Thread.CurrentThread.SetApartmentState(ApartmentState.Unknown);
Thread.CurrentThread.SetApartmentState(ApartmentState.STA);


var cafApp = ConsoleApp.Create()
    .ConfigureServices((context, _, services) =>
    {
        if (!string.IsNullOrEmpty(context.CommandName))
            AttachConsole();

        ConfigureCommonServices(services);
    });
cafApp.Add("", RunGuiAsync);
cafApp.Add<CliCommands>();

await cafApp.RunAsync(args).ConfigureAwait(false);

/// <summary>
/// GUI を起動します。
/// </summary>
/// <param name="toastActivated">-ToastActivated, Windows トースト通知から起動されたことを示します。</param>
static async Task RunGuiAsync(bool toastActivated = false)
{
    // Microsoft.Extensions.Hosting でサービスを構成し、Avalonia AppBuilder で起動する
    var host = new HostBuilder()
        .ConfigureServices((_, services) =>
        {
            ConfigureCommonServices(services);
            ConfigureGuiServices(services);
            // Avalonia Window と ViewModel を DI 登録 (Kamishibai の AddPresentation 相当)
            services.AddTransient<MainWindowViewModel>();
            services.AddTransient<MainWindow>();
        })
        .Build();

    App.Services = host.Services;
    await host.StartAsync();

    try
    {
        // Avalonia アプリを起動（ウィンドウが閉じるまでブロック）
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .StartWithClassicDesktopLifetime([]);
    }
    finally
    {
        await host.StopAsync();
    }
}

static void ConfigureCommonServices(IServiceCollection services)
{
    services.AddLogging(b => b.AddConsole());
    services.AddHttpClient("WondayWall", c => c.Timeout = TimeSpan.FromSeconds(30));
    services.AddHttpClient(
            "Gemini",
            c =>
            {
                c.Timeout = TimeSpan.FromMinutes(30);
                c.DefaultRequestHeaders.TryAddWithoutValidation("X-Server-Timeout", "1800");
            })
        .AddResilienceHandler("GoogleAiRetry", static builder => builder.AddRetry(new HttpRetryStrategyOptions()));
    services.AddSingleton<WallpaperService>();
    services.AddSingleton<AppConfigService>();
    services.AddSingleton<HistoryService>();
    services.AddSingleton<ContextService>();
    services.AddSingleton<GoogleAiService>();
    services.AddSingleton<GenerationCoordinator>();
    services.AddSingleton<TaskSchedulerService>();
}

static void ConfigureGuiServices(IServiceCollection services)
{
    services.AddHttpClient(
        "WondayWallUpdate",
        c =>
        {
            c.Timeout = TimeSpan.FromMinutes(10);
            c.DefaultRequestHeaders.UserAgent.ParseAdd("WondayWall");
        });
    services.AddSingleton<IGitHubClient>(_ => new GitHubClient(new ProductHeaderValue("WondayWall")));
    services.AddSingleton<UpdateChecker>();
    services.AddHostedService(sp => sp.GetRequiredService<UpdateChecker>());
}

static void AttachConsole()
{
    if (!PInvoke.AttachConsole(PInvoke.ATTACH_PARENT_PROCESS))
    {
#if DEBUG // デバッグビルドの場合はログ見たいのでコンソールを割り当てる
        PInvoke.AllocConsole();
#endif
    }

    var outputWriter = new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true };
    var errorWriter = new StreamWriter(Console.OpenStandardError()) { AutoFlush = true };
    Console.SetOut(outputWriter);
    Console.SetError(errorWriter);
}
