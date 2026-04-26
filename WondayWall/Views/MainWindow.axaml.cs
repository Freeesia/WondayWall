using Avalonia.Controls;
using Avalonia.Input;
using WondayWall.Models;
using WondayWall.ViewModels;

namespace WondayWall.Views;

public partial class MainWindow : Window
{
    /// <summary>デザイン時およびランタイムローダー向けのパラメーターなしコンストラクター</summary>
    public MainWindow()
    {
        InitializeComponent();
    }

    public MainWindow(MainWindowViewModel viewModel) : this()
    {
        DataContext = viewModel;
    }

    /// <summary>実行履歴をダブルクリックしたときに対象画像を開く</summary>
    private void HistoryDataGrid_OnDoubleTapped(object? sender, TappedEventArgs e)
    {
        if (sender is not DataGrid { SelectedItem: HistoryItem historyItem })
            return;

        if (DataContext is not MainWindowViewModel viewModel)
            return;

        viewModel.OpenHistoryImageCommand.Execute(historyItem);
    }
}
