using ConsoleAppFramework;
using Kamishibai;
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

// 単一ファイル配布でも Windows App SDK の埋め込みリソースを解決できるようにする。
Environment.SetEnvironmentVariable("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY", AppContext.BaseDirectory);

// GUI と Widget Provider の依存サービスは STA を必要とする。
Thread.CurrentThread.SetApartmentState(ApartmentState.Unknown);
Thread.CurrentThread.SetApartmentState(ApartmentState.STA);

var cafApp = ConsoleApp.Create()
    .ConfigureServices((context, _, services) =>
    {
        if (!string.IsNullOrEmpty(context.CommandName)
            && !string.Equals(context.CommandName, "widget-provider", StringComparison.OrdinalIgnoreCase))
            AttachConsole();

        ConfigureCommonServices(services);
    });
cafApp.Add("", RunGuiAsync);
cafApp.Add("widget-provider", RunWidgetProvider);
cafApp.Add<CliCommands>();

await cafApp.RunAsync(args).ConfigureAwait(false);

/// <summary>
/// GUI を起動します。
/// </summary>
/// <param name="toastActivated">-ToastActivated, Windows トースト通知から起動されたことを示します。</param>
static async Task RunGuiAsync(bool toastActivated = false)
{
    var builder = KamishibaiApplication<App, MainWindow>.CreateBuilder();
    ConfigureCommonServices(builder.Services);
    ConfigureGuiServices(builder.Services);
    builder.Services
        .AddPresentation<MainWindow, MainWindowViewModel>();
    var wpfApp = builder.Build();
    await wpfApp.RunAsync();
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
#if DEBUG
    services.AddSingleton<DummyNewsGenerator>();
    services.AddSingleton<DummyAiService>();
    services.AddSingleton<IAiService>(sp =>
        sp.GetRequiredService<AppConfigService>().Current.DebugConfig.UseDummyAiService
            ? sp.GetRequiredService<DummyAiService>()
            : sp.GetRequiredService<GoogleAiService>());
#else
    services.AddSingleton<IAiService>(sp => sp.GetRequiredService<GoogleAiService>());
#endif
    services.AddSingleton<GenerationCoordinator>();
    services.AddSingleton<TaskSchedulerService>();
    services.AddSingleton<WidgetHistoryService>();
    services.AddSingleton<WidgetActionService>();
    services.AddSingleton<WidgetCardBuilder>();
    services.AddSingleton<WondayWallWidgetProvider>();
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

static void RunWidgetProvider([FromServices] WondayWallWidgetProvider provider)
{
    WinRT.ComWrappersSupport.InitializeComWrappers();
    provider.RecoverRunningWidgets();

    using var registration = WidgetProviderRegistration.Register(provider);
    provider.ShutdownWaitHandle.WaitOne();
}
