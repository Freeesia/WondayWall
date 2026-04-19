using System.Windows.Input;
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
}
