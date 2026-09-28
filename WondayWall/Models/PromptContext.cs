using System.Text.Json.Serialization;

namespace WondayWall.Models;

public record PromptContext(
    IReadOnlyList<PromptCalendarEvent>? CalendarEvents = null,
    IReadOnlyList<PromptNewsTopic>? NewsTopics = null,
    string ImageSize = "1920x1080",
    string AspectRatio = "16:9",
    string? AdditionalConstraints = null);

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
    string? OgpImageUrl = null,
    // テキストモデルへのプロンプト構築時にNewsTopicsをJSONへ丸ごとシリアライズするため、
    // 画像バイナリをテキストプロンプトに巨大なBase64として埋め込まないようJsonIgnoreで除外する。
    // 画像本体は GenerateContentRequest.AddInlineData で別途送信する。
    [property: JsonIgnore] byte[]? OgpImageData = null,
    [property: JsonIgnore] string? OgpImageMimeType = null);
