using System.IO;
using System.Net.Http;
using System.Text.Json;
using GenerativeAI;
using GenerativeAI.Types;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GoogleAiService(AppConfigService configService, IHttpClientFactory httpClientFactory, ILogger<GoogleAiService> logger)
{
    private readonly HttpClient httpClient = httpClientFactory.CreateClient("WondayWall");
    private static readonly string FixedImageSavePath = Path.Combine(
        System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
        "WondayWall", "wallpapers");
    private static readonly JsonSerializerOptions JsonSerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };
    private static readonly Schema PromptSelectionResponseSchema = CreatePromptSelectionResponseSchema();

    public async Task<GeneratedImageInfo> GenerateWallpaperAsync(
        PromptContext context,
        CancellationToken ct = default)
    {
        var config = configService.Current;

        if (string.IsNullOrWhiteSpace(config.GoogleAiApiKey))
            throw new InvalidOperationException("Google AI API key is not configured.");

        // ステップ1: テキストモデルで詳細な画像プロンプトを生成（Google検索グラウンディングを有効化）
        var textModel = new GenerativeModel(config.GoogleAiApiKey, "gemini-3-flash-preview")
        {
            UseGoogleSearch = true,
        };
        var contextPrompt = BuildTextModelPrompt(context);
        var promptRequest = new GenerateContentRequest
        {
            GenerationConfig = new GenerationConfig
            {
                ResponseMimeType = "application/json",
                ResponseSchema = PromptSelectionResponseSchema,
            },
        };
        promptRequest.AddText(contextPrompt);

        var promptResponse = await textModel.GenerateContentAsync(promptRequest, cancellationToken: ct);
        var promptSelection = ParsePromptSelection(promptResponse.Text());
        var imagePrompt = promptSelection.ImagePrompt.Trim();

        // ステップ2: 画像モデルでアスペクト比・サイズを指定して壁紙を生成
        var displayInfo = DisplayHelper.GetDisplayInfo();
        var genConfig = new GenerationConfig
        {
            ResponseModalities = [Modality.IMAGE],
            ImageConfig = new ImageConfig
            {
                AspectRatio = displayInfo.AspectRatio,
                ImageSize = displayInfo.ImageSize,
            }
        };
        var imageModel = new GenerativeModel(config.GoogleAiApiKey, "gemini-3.1-flash-image-preview", genConfig)
        {
            UseGoogleSearch = true,
        };

        // テキストモデルが採用したニュースだけ、そのOGP画像を参照画像として添付する
        var selectedNewsIds = promptSelection.SelectedNewsIds.ToHashSet(StringComparer.Ordinal);
        var ogpUrls = (context.NewsTopics ?? [])
            .Where(newsTopic => selectedNewsIds.Contains(newsTopic.Id) && !string.IsNullOrWhiteSpace(newsTopic.OgpImageUrl))
            .Select(newsTopic => newsTopic.OgpImageUrl!)
            .Take(3)
            .ToList();
        var finalPrompt = ogpUrls.Count > 0
            ? $"{imagePrompt}\n\nReference images from the selected news topics are attached. " +
              "Incorporate their visual themes, color palette, and subject matter into the wallpaper design."
            : imagePrompt;

        var parts = new List<Part> { new Part(finalPrompt) };
        foreach (var imgUrl in ogpUrls)
        {
            try
            {
                // HTTPレスポンスからMIMEタイプを取得してインラインデータとして添付
                using var imgResponse = await httpClient.GetAsync(imgUrl, ct);
                imgResponse.EnsureSuccessStatusCode();
                var mimeType = imgResponse.Content.Headers.ContentType?.MediaType ?? "image/jpeg";
                var imgBytes = await imgResponse.Content.ReadAsByteArrayAsync(ct);
                parts.Add(new Part
                {
                    InlineData = new Blob
                    {
                        MimeType = mimeType,
                        Data = Convert.ToBase64String(imgBytes),
                    }
                });
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "OGP画像のダウンロードに失敗しました [{ImgUrl}]", imgUrl);
            }
        }

        var response = await imageModel.GenerateContentAsync(parts, cancellationToken: ct);

        var imageBytes = ExtractImageBytes(response);

        if (imageBytes == null || imageBytes.Length == 0)
            throw new InvalidOperationException("No image data returned from Google AI.");

        var filePath = FileNameHelper.GetImageFilePath(FixedImageSavePath);
        await File.WriteAllBytesAsync(filePath, imageBytes, ct);

        return new GeneratedImageInfo(
            FilePath: filePath,
            GeneratedAt: DateTime.Now,
            UsedPrompt: imagePrompt,
            SourceContext: context);
    }

    /// <summary>
    /// テキストモデルへ送るプロンプトを構築する。
    /// テキストモデルは候補コンテキストから採用要素を決め、画像生成用JSONを返す。
    /// </summary>
    private static string BuildTextModelPrompt(PromptContext context)
    {
        var parts = new List<string>
        {
            $$"""
            You are an expert desktop wallpaper image-generation prompt writer.
            You will be given calendar events, news topics, and optionally reference images from those news articles.
            You MUST aggressively use Google Search before writing the prompt.
            Research broadly and actively: run multiple targeted searches per topic (official sources, recent coverage,
            image references, and related background context), then cross-check recency and consistency.
            Prefer fresh, high-signal information and concrete visual details you can translate into imagery.
            Do not rely only on the user's short summaries when searchable context exists.
            Your task: review all candidate calendar events and news topics, decide which ones should materially influence
            the wallpaper, and then write a single detailed, creative English prompt for an image generation model
            ({{context.ImageSize}} resolution, {{context.AspectRatio}} aspect ratio) that creates a beautiful desktop wallpaper.

            The wallpaper should visually reflect the themes, mood, and atmosphere of the selected events and news.
            If reference images are supplied later, they will correspond only to selected news topics.
            Describe visual elements, style, mood, color palette, lighting, and composition in detail.
            No text, logos, or UI overlays. Wide landscape orientation unless aspect ratio specifies otherwise.

            For calendar events:
            - Only include POSITIVE events (celebrations, trips, parties, hobbies, achievements, social gatherings, etc.)
              in the visual design. Ignore NEGATIVE or NEUTRAL events (medical appointments, work deadlines,
              chores, administrative tasks, etc.), but do not let them suppress other event or news candidates.
            - Each event has a proximity tag indicating when it occurs. Use it to determine the visual weight:
              [today] or [tomorrow]: this event DOMINATES the entire image — make it the primary subject and theme,
                occupying nearly all visual elements.
              [in 2-3 days]: this event is a MAJOR visual theme, occupying 50–70% of the image's visual elements.
              [in 4-7 days]: this event is a MINOR accent or background element (15–30% of visual elements).
            - When multiple positive events are present, prioritize the ones happening sooner.
            - If the nearest event is NEGATIVE or NEUTRAL, ignore it and continue considering later positive events
              and news topics as potential primary themes.

            Return a response that matches the configured JSON schema.
            - imagePrompt must be a single detailed English prompt for the image model.
            - selectedNewsIds must contain only ids of news topics that materially influenced imagePrompt.
            - If no news topic is used, selectedNewsIds must be an empty array.
            - Do not output markdown fences or any extra explanation.
            """,
        };

        if ((context.CalendarEvents ?? []).Count > 0)
        {
            parts.Add($"Calendar event candidates (JSON):\n{SerializeCandidates(context.CalendarEvents)}");
        }

        if ((context.NewsTopics ?? []).Count > 0)
        {
            parts.Add($"News topic candidates (JSON):\n{SerializeCandidates(context.NewsTopics)}");
        }

        if (!string.IsNullOrWhiteSpace(context.AdditionalConstraints))
        {
            parts.Add($"Additional instructions: {context.AdditionalConstraints}");
        }

        return string.Join("\n\n", parts);
    }

    private static string SerializeCandidates<T>(IReadOnlyList<T>? items)
        => JsonSerializer.Serialize(items ?? Array.Empty<T>(), JsonSerializerOptions);

    private static Schema CreatePromptSelectionResponseSchema()
        => GoogleSchemaHelper.ConvertToSchema<PromptSelectionResponse>(JsonSerializerOptions);

    private static PromptSelectionResponse ParsePromptSelection(string? responseText)
    {
        if (string.IsNullOrWhiteSpace(responseText))
            throw new InvalidOperationException("Google AI did not return a structured prompt response.");

        try
        {
            var response = JsonSerializer.Deserialize<PromptSelectionResponse>(responseText, JsonSerializerOptions);
            if (response == null || string.IsNullOrWhiteSpace(response.ImagePrompt))
                throw new InvalidOperationException("Google AI returned a prompt response without imagePrompt.");

            response.SelectedNewsIds = (response.SelectedNewsIds ?? [])
                .Where(id => !string.IsNullOrWhiteSpace(id))
                .Select(id => id.Trim())
                .Distinct(StringComparer.Ordinal)
                .ToList();

            return response;
        }
        catch (JsonException ex)
        {
            throw new InvalidOperationException("Failed to parse Google AI structured prompt response.", ex);
        }
    }

    private static byte[]? ExtractImageBytes(GenerateContentResponse response)
    {
        foreach (var candidate in response.Candidates ?? [])
        {
            foreach (var part in candidate.Content?.Parts ?? [])
            {
                if (part.InlineData?.MimeType?.StartsWith("image/") == true &&
                    part.InlineData.Data != null)
                {
                    return Convert.FromBase64String(part.InlineData.Data);
                }
            }
        }
        return null;
    }

    private sealed class PromptSelectionResponse
    {
        public required string ImagePrompt { get; init; }

        public required List<string> SelectedNewsIds { get; set; }
    }
}
