namespace WondayWall.Models;

public record PromptContext(
    IReadOnlyList<PromptCalendarEvent>? CalendarEvents = null,
    IReadOnlyList<PromptNewsTopic>? NewsTopics = null,
    string ImageSize = "1920x1080",
    string AspectRatio = "16:9",
    string? AdditionalConstraints = null,
    /// <summary>ベースとして使用するこのアプリが生成した壁紙のファイルパス</summary>
    string? BaseImagePath = null,
    /// <summary>ベース壁紙生成時に使用したカレンダーイベント（削除要素判定用）</summary>
    IReadOnlyList<CalendarEventItem>? PreviousCalendarEvents = null,
    /// <summary>ベース壁紙生成時に使用したニューストピック（削除要素判定用）</summary>
    IReadOnlyList<NewsTopicItem>? PreviousNewsTopics = null);

public record PromptCalendarEvent(
    string Id,
    string Title,
    string ProximityTag,
    DateTime StartTime,
    DateTime? EndTime = null,
    string? Location = null,
    string? Description = null);

public record PromptNewsTopic(
    string Id,
    string Title,
    string? Summary = null,
    string? Url = null,
    DateTime? PublishedAt = null,
    string? OgpImageUrl = null);
