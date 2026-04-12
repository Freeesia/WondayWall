using System.IO;
using System.Net.Http;
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

    public async Task<GeneratedImageInfo> GenerateWallpaperAsync(
        PromptContext context,
        CancellationToken ct = default)
    {
        var config = configService.Current;

        if (string.IsNullOrWhiteSpace(config.GoogleAiApiKey))
            throw new InvalidOperationException("Google AI API key is not configured.");

        // ステップ1: テキストモデルで詳細な画像プロンプトを生成
        var textModel = new GenerativeModel(config.GoogleAiApiKey, "gemini-3-flash-preview");
        var contextPrompt = BuildTextModelPrompt(context);
        var promptResponse = await textModel.GenerateContentAsync(contextPrompt, cancellationToken: ct);
        var imagePrompt = promptResponse.Text() ?? contextPrompt;

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
        var imageModel = new GenerativeModel(config.GoogleAiApiKey, "gemini-3.1-flash-image-preview", genConfig);

        // OGP画像がある場合はインラインデータとして添付し、プロンプトにもその旨を付記
        var ogpUrls = (context.OgpImageUrls ?? []).Take(3).ToList();
        var finalPrompt = ogpUrls.Count > 0
            ? $"{imagePrompt}\n\nReference images from the related news articles are attached. " +
              "Incorporate their visual themes, colour palette, and subject matter into the wallpaper design."
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
            GeneratedAt: DateTimeOffset.UtcNow,
            UsedPrompt: imagePrompt,
            SourceContext: context);
    }

    /// <summary>
    /// テキストモデルへ送るプロンプトを構築する。
    /// テキストモデルはこのプロンプトを受け取り、画像生成モデル向けの詳細な英語プロンプトを返す。
    /// </summary>
    private static string BuildTextModelPrompt(PromptContext context)
    {
        var parts = new List<string>
        {
            $"""
            You are an expert desktop wallpaper image-generation prompt writer.
            You will be given calendar events, news topics, and optionally reference images from those news articles.
            Your task: write a single detailed, creative English prompt for an image generation model
            ({context.ImageSize} resolution, {context.AspectRatio} aspect ratio) that creates a beautiful desktop wallpaper.

            The wallpaper should visually reflect the themes, mood, and atmosphere of the provided events and news.
            If reference images are supplied, incorporate their colour palette, visual motifs, and subject matter.
            Describe visual elements, style, mood, colour palette, lighting, and composition in detail.
            No text, logos, or UI overlays. Wide landscape orientation unless aspect ratio specifies otherwise.
            Output only the English image generation prompt — no explanation or preamble.
            """,
        };

        if (!string.IsNullOrWhiteSpace(context.EventSummary))
        {
            parts.Add($"Upcoming calendar events:\n{context.EventSummary}");
        }

        if (!string.IsNullOrWhiteSpace(context.NewsSummary))
        {
            parts.Add($"Current news topics:\n{context.NewsSummary}");
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
}
