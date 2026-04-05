using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace WondayWall.Views;

public partial class MainWindow : FluentWindow
{
    public MainWindow()
    {
        SystemThemeWatcher.Watch(this);
        InitializeComponent();
    }
}
