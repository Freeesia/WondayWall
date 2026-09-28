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
using AppResources = WondayWall.Properties.Resources;

namespace WondayWall.Services;

public class GoogleAiService(
    AppConfigService configService,
    IHttpClientFactory httpClientFactory,
    ILogger<GoogleAiService> logger) : IAiService
{
    private const string GoogleAiApiKeyPageUrl = "https://aistudio.google.com/app/api-keys";
    private static string PaidTierRequiredMessage => AppResources.GoogleAiBillingError + GoogleAiApiKeyPageUrl;
    private const string TextModelName = "gemini-3-flash-preview";
    private const string ImageModelName = "gemini-3.1-flash-image-preview";

    private readonly HttpClient ogpHttpClient = httpClientFactory.CreateClient("WondayWall");
    private readonly HttpClient geminiHttpClient = httpClientFactory.CreateClient("Gemini");
    private static readonly JsonSerializerOptions JsonSerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public async Task<GeneratedImageInfo> GenerateWallpaperAsync(
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        CancellationToken ct = default)
    {
        var promptResult = await GeneratePromptAsync(context, serviceTier, ct).ConfigureAwait(false);
        var contextWithOgp = await FetchOgpImagesAsync(context, promptResult.SelectedNewsIds, ct).ConfigureAwait(false);
        return await GenerateImageFromPromptAsync(
            promptResult.ImagePrompt,
            contextWithOgp,
            promptResult.ServiceTier,
            ct).ConfigureAwait(false);
    }

    public async Task<PromptGenerationResult> GeneratePromptAsync(
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        CancellationToken cancellationToken = default)
    {
        var config = configService.Current;

        if (string.IsNullOrWhiteSpace(config.GoogleAiApiKey))
            throw new InvalidOperationException("Google AI API key is not configured.");

        var result = await GeneratePromptSelectionWithFallbackAsync(
            context,
            serviceTier,
            config.GoogleAiApiKey,
            cancellationToken).ConfigureAwait(false);
        var selectedNews = ResolveSelectedNewsTopics(context, result.PromptSelection.SelectedNewsIds);

        return new PromptGenerationResult(
            ImagePrompt: result.PromptSelection.ImagePrompt,
            SelectedNewsTopics: selectedNews,
            SelectedNewsIds: result.PromptSelection.SelectedNewsIds,
            ServiceTier: result.ServiceTier);
    }

    public async Task<PromptContext> FetchOgpImagesAsync(
        PromptContext context,
        IReadOnlyList<string> selectedNewsIds,
        CancellationToken cancellationToken = default)
    {
        var selectedIds = selectedNewsIds.ToHashSet(StringComparer.Ordinal);
        var newsTopics = (context.NewsTopics ?? []).ToList();
        var targets = newsTopics
            .Select((topic, index) => (Topic: topic, Index: index))
            .Where(item => selectedIds.Contains(item.Topic.Id)
                && !string.IsNullOrWhiteSpace(item.Topic.OgpImageUrl))
            .Take(3)
            .ToList();

        var downloads = await Task.WhenAll(targets.Select(async item =>
        {
            try
            {
                using var response = await ogpHttpClient.GetAsync(
                    item.Topic.OgpImageUrl,
                    cancellationToken).ConfigureAwait(false);
                response.EnsureSuccessStatusCode();
                var mimeType = response.Content.Headers.ContentType?.MediaType ?? "image/jpeg";
                var data = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
                return (Success: true, item.Index, Data: data, MimeType: mimeType);
            }
            catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
            {
                logger.LogWarning(ex, "OGP画像のダウンロードに失敗しました [{ImgUrl}]", item.Topic.OgpImageUrl);
                return (Success: false, item.Index, Data: Array.Empty<byte>(), MimeType: "image/jpeg");
            }
        })).ConfigureAwait(false);

        foreach (var download in downloads.Where(item => item.Success))
        {
            newsTopics[download.Index] = newsTopics[download.Index] with
            {
                OgpImageData = download.Data,
                OgpImageMimeType = download.MimeType,
            };
        }

        return context with { NewsTopics = newsTopics };
    }

    public async Task<GeneratedImageInfo> GenerateImageFromPromptAsync(
        string imagePrompt,
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        CancellationToken cancellationToken = default)
    {
        var config = configService.Current;
        if (string.IsNullOrWhiteSpace(config.GoogleAiApiKey))
            throw new InvalidOperationException("Google AI API key is not configured.");

        var imageRequest = BuildImageRequest(context, imagePrompt);
        return await GenerateImageWithFallbackAsync(
            context,
            imagePrompt,
            imageRequest,
            serviceTier,
            config.GoogleAiApiKey,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<PromptSelectionResult> GeneratePromptSelectionWithFallbackAsync(
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        string apiKey,
        CancellationToken ct)
    {
        if (serviceTier != GoogleAiServiceTier.Flex)
            return await GeneratePromptSelectionAsync(context, GoogleAiServiceTier.Standard, apiKey, ct).ConfigureAwait(false);

        try
        {
            return await GeneratePromptSelectionAsync(context, GoogleAiServiceTier.Flex, apiKey, ct).ConfigureAwait(false);
        }
        catch (Exception ex) when (!ct.IsCancellationRequested)
        {
            logger.LogWarning(ex, "画像プロンプト生成の Flex 呼び出しが規定回数失敗したため Standard モードで再試行します。");
            return await GeneratePromptSelectionAsync(context, GoogleAiServiceTier.Standard, apiKey, ct).ConfigureAwait(false);
        }
    }

    private async Task<PromptSelectionResult> GeneratePromptSelectionAsync(
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        string apiKey,
        CancellationToken ct)
    {
        // ステップ1: テキストモデルで詳細な画像プロンプトを生成（Google検索グラウンディングを有効化）
        var textModel = new GenerativeModelEx(apiKey, TextModelName, httpClient: geminiHttpClient, serviceTier: serviceTier);
        var contextPrompt = BuildTextModelPrompt(context);
        var promptRequest = new GenerateContentRequest();
        promptRequest.UseJsonMode<PromptSelectionResponse>(JsonSerializerOptions);
        promptRequest.AddText(contextPrompt);
        AddGoogleSearchTool(promptRequest);

        GenerateContentResponse promptResponse;
        try
        {
            promptResponse = await textModel.GenerateContentAsync(promptRequest, ct);
        }
        catch (ApiException ex) when (IsPaidTierRequiredError(ex))
        {
            throw new InvalidOperationException(PaidTierRequiredMessage, ex);
        }
        var promptSelection = promptResponse.ToObject<PromptSelectionResponse>(JsonSerializerOptions);

        if (promptSelection == null || string.IsNullOrWhiteSpace(promptSelection.ImagePrompt))
            throw new InvalidOperationException("Google AI returned an invalid structured prompt response.");

        promptSelection.SelectedNewsIds = (promptSelection.SelectedNewsIds ?? [])
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .Distinct(StringComparer.Ordinal)
            .ToList();
        promptSelection.ImagePrompt = promptSelection.ImagePrompt.Trim();

        return new PromptSelectionResult(promptSelection, serviceTier);
    }

    private async Task<GeneratedImageInfo> GenerateImageWithFallbackAsync(
        PromptContext context,
        string imagePrompt,
        GenerateContentRequest imageRequest,
        GoogleAiServiceTier serviceTier,
        string apiKey,
        CancellationToken ct)
    {
        if (serviceTier != GoogleAiServiceTier.Flex)
        {
            return await GenerateImageAsync(context, imagePrompt, imageRequest, GoogleAiServiceTier.Standard, apiKey, ct).ConfigureAwait(false);
        }

        try
        {
            return await GenerateImageAsync(context, imagePrompt, imageRequest, GoogleAiServiceTier.Flex, apiKey, ct).ConfigureAwait(false);
        }
        catch (Exception ex) when (!ct.IsCancellationRequested)
        {
            logger.LogWarning(ex, "画像生成の Flex 呼び出しが規定回数失敗したため、生成済みプロンプトを使って Standard モードで再試行します。");
            return await GenerateImageAsync(context, imagePrompt, imageRequest, GoogleAiServiceTier.Standard, apiKey, ct).ConfigureAwait(false);
        }
    }

    private async Task<GeneratedImageInfo> GenerateImageAsync(
        PromptContext context,
        string imagePrompt,
        GenerateContentRequest imageRequest,
        GoogleAiServiceTier serviceTier,
        string apiKey,
        CancellationToken ct)
    {
        // ステップ2: 画像モデルでアスペクト比・サイズを指定して壁紙を生成
        var imageModel = new GenerativeModelEx(apiKey, ImageModelName, httpClient: geminiHttpClient, serviceTier: serviceTier);

        GenerateContentResponse response;
        try
        {
            response = await imageModel.GenerateContentAsync(imageRequest, ct).ConfigureAwait(false);
        }
        catch (ApiException ex) when (IsPaidTierRequiredError(ex))
        {
            throw new InvalidOperationException(PaidTierRequiredMessage, ex);
        }

        var imageData = ExtractImageBytes(response);

        if (imageData == null || imageData.Value.Bytes.Length == 0)
            throw new InvalidOperationException("No image data returned from Google AI.");

        var filePath = FileNameHelper.GetImageFilePath(PathUtility.WallpaperDirectory, extension: imageData.Value.Extension);
        await File.WriteAllBytesAsync(filePath, imageData.Value.Bytes, ct).ConfigureAwait(false);

        return new(filePath, DateTime.Now, imagePrompt, serviceTier, context);
    }

    private static GenerateContentRequest BuildImageRequest(PromptContext context, string imagePrompt)
    {
        var referenceImages = (context.NewsTopics ?? [])
            .Where(topic => topic.OgpImageData is { Length: > 0 })
            .Take(3)
            .ToList();
        var finalPrompt = referenceImages.Count > 0
            ? $$"""
              {{imagePrompt}}

              Reference images from the selected news topics are attached. Incorporate their visual themes, color palette, and subject matter into the wallpaper design.
              """
            : imagePrompt;

        var imageRequest = new GenerateContentRequest();

        imageRequest.AddText(finalPrompt);
        foreach (var referenceImage in referenceImages)
        {
            imageRequest.AddInlineData(
                Convert.ToBase64String(referenceImage.OgpImageData!),
                referenceImage.OgpImageMimeType ?? "image/jpeg");
        }

        var displayInfo = DisplayHelper.GetDisplayInfo();
        imageRequest.GenerationConfig = new GenerationConfig
        {
            ResponseModalities = [Modality.IMAGE],
            ImageConfig = new ImageConfig
            {
                AspectRatio = displayInfo.AspectRatio,
                ImageSize = displayInfo.ImageSize,
            }
        };
        AddGoogleSearchTool(imageRequest);

        return imageRequest;
    }

    private static List<NewsTopicItem> ResolveSelectedNewsTopics(
        PromptContext context,
        IReadOnlyList<string> selectedNewsIds)
    {
        var topicsById = (context.NewsTopics ?? [])
            .GroupBy(topic => topic.Id, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);

        return selectedNewsIds
            .Where(topicsById.ContainsKey)
            .Select(id => topicsById[id])
            .Select(topic => new NewsTopicItem(
                Title: topic.Title,
                Summary: topic.Summary,
                Url: topic.Url,
                PublishedAt: topic.PublishedAt,
                OgpImageUrl: topic.OgpImageUrl))
            .ToList();
    }

    private static void AddGoogleSearchTool(GenerateContentRequest request)
    {
        request.Tools ??= [];
        if (request.Tools.Any(static tool => tool.GoogleSearch != null))
            return;

        request.Tools.Add(new Tool
        {
            GoogleSearch = new GoogleSearchTool(),
        });
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

    private static (byte[] Bytes, string Extension)? ExtractImageBytes(GenerateContentResponse response)
    {
        foreach (var candidate in response.Candidates ?? [])
        {
            foreach (var part in candidate.Content?.Parts ?? [])
            {
                if (part.InlineData?.MimeType?.StartsWith("image/", StringComparison.OrdinalIgnoreCase) == true &&
                    part.InlineData.Data != null)
                {
                    var extension = part.InlineData.MimeType["image/".Length..].Trim().ToLowerInvariant();
                    if (extension.Length == 0)
                        continue;

                    return (Convert.FromBase64String(part.InlineData.Data), extension);
                }
            }
        }
        return null;
    }

    private sealed class PromptSelectionResponse
    {
        public required string ImagePrompt { get; set; }

        public required List<string> SelectedNewsIds { get; set; }
    }

    private sealed record PromptSelectionResult(
        PromptSelectionResponse PromptSelection,
        GoogleAiServiceTier ServiceTier);

    private static bool IsPaidTierRequiredError(ApiException ex)
        => ex is { ErrorCode: 400, ErrorStatus: "FAILED_PRECONDITION" }
            or { ErrorCode: 429, ErrorStatus: "RESOURCE_EXHAUSTED" };
}
