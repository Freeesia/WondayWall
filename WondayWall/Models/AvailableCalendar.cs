namespace WondayWall.Models;

public class AvailableCalendar
{
    public string Id { get; init; } = string.Empty;
    public string Summary { get; init; } = string.Empty;
    public bool IsPrimary { get; init; }
    /// <summary>UI上のチェックボックスにバインドされるため公開セッターが必要</summary>
    public bool IsSelected { get; set; }
}
