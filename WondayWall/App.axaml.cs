using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Microsoft.Extensions.DependencyInjection;
using WondayWall.Views;

namespace WondayWall;

public partial class App : Application
{
    /// <summary>DIサービスプロバイダー。Program.cs で Avalonia 起動前に設定される。</summary>
    internal static IServiceProvider Services { get; set; } = null!;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // DI コンテナから MainWindow を解決（ViewModel も DI で注入される）
            desktop.MainWindow = Services.GetRequiredService<MainWindow>();
        }
        base.OnFrameworkInitializationCompleted();
    }
}
