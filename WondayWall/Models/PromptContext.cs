namespace WondayWall.Models;

public record PromptContext(
    string EventSummary = "",
    string NewsSummary = "",
    string ImageSize = "1920x1080",
    string AspectRatio = "16:9",
    string? AdditionalConstraints = null,
    IReadOnlyList<string>? OgpImageUrls = null,
    /// <summary>ベースとして使用するこのアプリが生成した壁紙のファイルパス</summary>
    string? BaseImagePath = null);
