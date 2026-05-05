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
        // タイトルバー拡張設定はコードビハインドで設定 (XAML コンパイラが認識できないため)
        ExtendClientAreaToDecorationsHint = true;

        InitializeComponent();
        DataContext = viewModel;

        // Padding.Top がタイトルバー高さになるので Row[0] に反映する
        PropertyChanged += (_, e) =>
        {
            if (e.Property == PaddingProperty && Padding.Top > 0
                && this.FindControl<Grid>("RootGrid") is { } grid
                && grid.RowDefinitions.Count > 0)
            {
                grid.RowDefinitions[0].Height = new GridLength(Padding.Top);
            }
        };
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
