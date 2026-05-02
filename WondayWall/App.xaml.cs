using System.Globalization;
using System.Windows;
using System.Windows.Markup;

namespace WondayWall;

public partial class App : Application
{
    private readonly TaskCompletionSource _startupCompletion = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public App()
    {
        FrameworkElement.LanguageProperty.OverrideMetadata(
            typeof(FrameworkElement),
            new FrameworkPropertyMetadata(XmlLanguage.GetLanguage(CultureInfo.CurrentUICulture.IetfLanguageTag)));
        InitializeComponent();
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _startupCompletion.TrySetResult();
    }

    public Task WaitForStartupAsync()
        => _startupCompletion.Task;
}
