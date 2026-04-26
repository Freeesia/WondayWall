using System.Diagnostics;
using System.Windows.Input;
using System.Windows.Navigation;
using WondayWall.Models;
using WondayWall.ViewModels;
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

    private void HistoryListView_OnMouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Wpf.Ui.Controls.ListView { SelectedItem: HistoryItem historyItem })
            return;

        if (DataContext is not MainWindowViewModel viewModel)
            return;

        viewModel.OpenHistoryImageCommand.Execute(historyItem);
    }

    private void ApiKeyLink_RequestNavigate(object sender, RequestNavigateEventArgs e)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = e.Uri.AbsoluteUri,
            UseShellExecute = true,
        });
        e.Handled = true;
    }
}
