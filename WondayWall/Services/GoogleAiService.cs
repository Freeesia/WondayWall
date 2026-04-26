using System.IO;
using System.Net.Http;
using System.Text.Json;
using GenerativeAI;
using GenerativeAI.Exceptions;
using GenerativeAI.Types;
using Microsoft.Extensions.Logging;
using WondayWall.ComponentModel;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GoogleAiService(AppConfigService configService, IHttpClientFactory httpClientFactory, ILogger<GoogleAiService> logger)
{
    private const string GoogleAiApiKeyPageUrl = "https://aistudio.google.com/app/api-keys";
    private const string PaidTierRequiredMessage =
        "無料枠または課金未設定の Google AI API キーでは、この画像生成機能を利用できません。Google AI Studio で課金設定済みのプロジェクト/APIキーを確認してください: "
        + GoogleAiApiKeyPageUrl;

    private readonly HttpClient httpClient = httpClientFactory.CreateClient("WondayWall");
    private static readonly string FixedImageSavePath = Path.Combine(
        System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData),
        "WondayWall", "wallpapers");
    private static readonly JsonSerializerOptions JsonSerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public async Task<GeneratedImageInfo> GenerateWallpaperAsync(
        PromptContext context,
        CancellationToken ct = default)
    {
        var config = configService.Current;

        if (string.IsNullOrWhiteSpace(config.GoogleAiApiKey))
            throw new InvalidOperationException("Google AI API key is not configured.");

        // ステップ1: テキストモデルで詳細な画像プロンプトを生成（Google検索グラウンディングを有効化）
        var textModel = new GenerativeModelEx(
            config.GoogleAiApiKey,
            "gemini-3-flash-preview",
            httpClient: httpClient)
        {
            UseGoogleSearch = true,
            UseJsonMode = true,
        };
        var contextPrompt = BuildTextModelPrompt(context);
        var promptRequest = new GenerateContentRequest();
        promptRequest.UseJsonMode<PromptSelectionResponse>(JsonSerializerOptions);
        promptRequest.AddText(contextPrompt);

        PromptSelectionResponse? promptSelection;
        try
        {
            promptSelection = await textModel.GenerateObjectAsync<PromptSelectionResponse>(promptRequest, ct);
        }
        catch (ApiException ex) when (IsPaidTierRequiredError(ex))
        {
            throw new InvalidOperationException(PaidTierRequiredMessage, ex);
        }

        if (promptSelection == null || string.IsNullOrWhiteSpace(promptSelection.ImagePrompt))
            throw new InvalidOperationException("Google AI returned an invalid structured prompt response.");

        promptSelection.SelectedNewsIds = (promptSelection.SelectedNewsIds ?? [])
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .Distinct(StringComparer.Ordinal)
            .ToList();
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
        var imageModel = new GenerativeModel(
            config.GoogleAiApiKey,
            "gemini-3.1-flash-image-preview",
            genConfig,
            httpClient: httpClient)
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
            ? $$"""
              {{imagePrompt}}

              Reference images from the selected news topics are attached. Incorporate their visual themes, color palette, and subject matter into the wallpaper design.
              """
            : imagePrompt;

        var imageRequest = new GenerateContentRequest();

        // ベース壁紙がある場合はインラインデータとして先頭に付加し、プロンプトにも指示を追加
        if (!string.IsNullOrEmpty(context.BaseImagePath) && File.Exists(context.BaseImagePath))
        {
            var baseImageBytes = await File.ReadAllBytesAsync(context.BaseImagePath, ct);
            var baseMimeType = GetMimeTypeFromPath(context.BaseImagePath);
            imageRequest.AddInlineData(Convert.ToBase64String(baseImageBytes), baseMimeType);
            // ベース画像を参照しつつ、現在のテーマに合わない要素を整理する指示を追加
            imageRequest.AddText(
                $$"""
                The current wallpaper is provided as the base image.
                Create a new wallpaper that evolves gradually from this base.
                Visually inspect the base wallpaper and compare it against the current prompt.
                Treat the current prompt's events, news themes, and mood as the source of truth.
                Remove or replace any subject, motif, decoration, or symbolic element from the base image that no longer matches the current prompt.
                When the base image conflicts with the current prompt, prioritize the current prompt while preserving the base image's overall composition, color palette, and artistic style.
                Preserve the overall composition, color palette, and artistic style of the base wallpaper. Incorporate the new themes and events subtly — avoid drastic visual changes.

                {{finalPrompt}}
                """);
        }
        else
        {
            imageRequest.AddText(finalPrompt);
        }
        foreach (var imgUrl in ogpUrls)
        {
            try
            {
                // HTTPレスポンスからMIMEタイプを取得してインラインデータとして添付
                using var imgResponse = await httpClient.GetAsync(imgUrl, ct);
                imgResponse.EnsureSuccessStatusCode();
                var mimeType = imgResponse.Content.Headers.ContentType?.MediaType ?? "image/jpeg";
                var imgBytes = await imgResponse.Content.ReadAsByteArrayAsync(ct);
                imageRequest.AddInlineData(Convert.ToBase64String(imgBytes), mimeType);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "OGP画像のダウンロードに失敗しました [{ImgUrl}]", imgUrl);
            }
        }

        GenerateContentResponse response;
        try
        {
            response = await imageModel.GenerateContentAsync(imageRequest, cancellationToken: ct);
        }
        catch (ApiException ex) when (IsPaidTierRequiredError(ex))
        {
            throw new InvalidOperationException(PaidTierRequiredMessage, ex);
        }

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

        if (!string.IsNullOrEmpty(context.BaseImagePath) && File.Exists(context.BaseImagePath))
        {
            parts.Add(
                """
                A base wallpaper image will be supplied to the image model.
                Preserve the overall composition, color palette, and artistic style of the base wallpaper.
                Incorporate the new themes and events subtly — avoid drastic visual changes.
                """);
        }

        if ((context.CalendarEvents ?? []).Count > 0)
        {
            parts.Add(
                $$"""
                Calendar event candidates (JSON):
                {{JsonSerializer.Serialize(context.CalendarEvents, JsonSerializerOptions)}}
                """);
        }

        if ((context.NewsTopics ?? []).Count > 0)
        {
            parts.Add(
                $$"""
                News topic candidates (JSON):
                {{JsonSerializer.Serialize(context.NewsTopics, JsonSerializerOptions)}}
                """);
        }

        if (!string.IsNullOrWhiteSpace(context.AdditionalConstraints))
        {
            parts.Add($"Additional instructions: {context.AdditionalConstraints}");
        }

        return string.Join("\n\n", parts);
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

    /// <summary>ファイルパスの拡張子からMIMEタイプを返す</summary>
    private static string GetMimeTypeFromPath(string filePath)
    {
        return Path.GetExtension(filePath).ToLowerInvariant() switch
        {
            ".jpg" or ".jpeg" => "image/jpeg",
            ".png" => "image/png",
            ".webp" => "image/webp",
            _ => "image/jpeg",
        };
    }

    private sealed class PromptSelectionResponse
    {
        public required string ImagePrompt { get; init; }

        public required List<string> SelectedNewsIds { get; set; }
    }

    private static bool IsPaidTierRequiredError(ApiException ex)
        => ex is { ErrorCode: 400, ErrorStatus: "FAILED_PRECONDITION" }
            or { ErrorCode: 429, ErrorStatus: "RESOURCE_EXHAUSTED" };
}
