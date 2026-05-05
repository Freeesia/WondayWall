using Avalonia.Controls;
using Avalonia.Input;
using WondayWall.Models;
using WondayWall.ViewModels;

namespace WondayWall.Views;

public partial class MainWindow : Window
{
    // Avalonia XAML ローダー用パラメータなしコンストラクタ
    public MainWindow() { }

    public MainWindow(MainWindowViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }

    /// <summary>履歴リストのダブルクリックで画像を開く</summary>
    private void HistoryListView_OnDoubleTapped(object? sender, TappedEventArgs e)
    {
        if (sender is not DataGrid { SelectedItem: HistoryItem historyItem })
            return;

        if (DataContext is not MainWindowViewModel viewModel)
            return;

        viewModel.OpenHistoryImageCommand.Execute(historyItem);
    }
}
