using ConsoleAppFramework;
using Kamishibai;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Polly;
using Polly.Retry;
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
    services.AddHttpClient("Gemini", c => c.Timeout = TimeSpan.FromMinutes(10));
    services.AddResiliencePipeline(GoogleAiService.FlexRetryPipelineName, static (builder, context) =>
    {
        var logger = context.ServiceProvider.GetRequiredService<ILogger<GoogleAiService>>();
        builder.AddRetry(new RetryStrategyOptions
        {
            MaxRetryAttempts = GoogleAiService.MaxFlexAttempts - 1,
            DelayGenerator = static args => new ValueTask<TimeSpan?>(
                GoogleAiService.GetFlexRetryDelay(args.AttemptNumber + 1)),
            ShouldHandle = static args =>
            {
                var exception = args.Outcome.Exception;
                return new ValueTask<bool>(
                    exception != null
                    && GoogleAiService.IsRetryableFlexFailure(exception, args.Context.CancellationToken));
            },
            OnRetry = args =>
            {
                var failedAttempt = args.AttemptNumber + 1;
                logger.LogWarning(
                    args.Outcome.Exception,
                    "Google AI Flex 呼び出しに失敗しました ({Attempt}/{MaxAttempts})。{DelaySeconds} 秒後に再試行します。",
                    failedAttempt,
                    GoogleAiService.MaxFlexAttempts,
                    args.RetryDelay.TotalSeconds);
                return default;
            },
        });
    });
    services.AddSingleton<WallpaperService>();
    services.AddSingleton<AppConfigService>();
    services.AddSingleton<HistoryService>();
    services.AddSingleton<ContextService>();
    services.AddSingleton<GoogleAiService>();
    services.AddSingleton<GenerationCoordinator>();
    services.AddSingleton<TaskSchedulerService>();
}
