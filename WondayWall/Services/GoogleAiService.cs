using System.IO;
using System.Net.Http;
using GenerativeAI;
using GenerativeAI.Types;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GoogleAiService(AppConfigService configService)
{
    private static readonly string FixedImageSavePath = Path.Combine(
        System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
        "WondayWall", "wallpapers");

    private static readonly HttpClient SharedHttpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(30),
    };

    public async Task<GeneratedImageInfo> GenerateWallpaperAsync(
        PromptContext context,
        CancellationToken ct = default)
    {
        var config = configService.Current;

        if (string.IsNullOrWhiteSpace(config.GoogleAiApiKey))
            throw new InvalidOperationException("Google AI API key is not configured.");

        // ステップ1: テキストモデルで詳細な画像プロンプトを生成
        var textModel = new GenerativeModel(config.GoogleAiApiKey, "gemini-3-flash-preview");
        var contextPrompt = BuildContextPrompt(context);
        var promptResponse = await textModel.GenerateContentAsync(contextPrompt, cancellationToken: ct);
        var imagePrompt = promptResponse.Text() ?? contextPrompt;

        // ステップ2: 画像モデルでアスペクト比・サイズを指定して壁紙を生成
        var genConfig = new GenerationConfig
        {
            ResponseModalities = [Modality.IMAGE],
            ImageConfig = new ImageConfig
            {
                AspectRatio = context.AspectRatio,
                ImageSize = ImageConfigValues.ImageSizes.Size2K,
            }
        };
        var imageModel = new GenerativeModel(config.GoogleAiApiKey, "gemini-3.1-flash-image-preview", genConfig);

        // OGP画像がある場合はインラインデータとして添付
        var parts = new List<Part> { new Part(imagePrompt) };
        foreach (var imgUrl in context.OgpImageUrls.Take(3))
        {
            try
            {
                // HTTPレスポンスからMIMEタイプを取得してインラインデータとして添付
                using var imgResponse = await SharedHttpClient.GetAsync(imgUrl, ct);
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
                // OGP画像ダウンロード失敗は無視
                Console.Error.WriteLine($"OGP image download failed [{imgUrl}]: {ex.Message}");
            }
        }

        var response = await imageModel.GenerateContentAsync(parts, cancellationToken: ct);

        var imageBytes = ExtractImageBytes(response);

        if (imageBytes == null || imageBytes.Length == 0)
            throw new InvalidOperationException("No image data returned from Google AI.");

        var filePath = FileNameHelper.GetImageFilePath(FixedImageSavePath);
        await File.WriteAllBytesAsync(filePath, imageBytes, ct);

        return new GeneratedImageInfo
        {
            FilePath = filePath,
            GeneratedAt = DateTimeOffset.UtcNow,
            UsedPrompt = imagePrompt,
            SourceContext = context,
        };
    }

    private static string BuildContextPrompt(PromptContext context)
    {
        var parts = new List<string>
        {
            $"Create a beautiful desktop wallpaper image ({context.ImageSize} resolution).",
            "The image should be visually stunning, high quality, and suitable as a desktop background.",
        };

        if (!string.IsNullOrWhiteSpace(context.EventSummary) &&
            context.EventSummary != "No upcoming calendar events.")
        {
            parts.Add($"Upcoming schedule context:\n{context.EventSummary}");
        }

        if (!string.IsNullOrWhiteSpace(context.NewsSummary) &&
            context.NewsSummary != "No relevant news topics.")
        {
            parts.Add($"Current news themes:\n{context.NewsSummary}");
        }

        if (context.AtmosphereKeywords.Count > 0)
        {
            parts.Add($"Interests and atmosphere: {string.Join(", ", context.AtmosphereKeywords)}");
        }

        if (!string.IsNullOrWhiteSpace(context.AdditionalConstraints))
        {
            parts.Add(context.AdditionalConstraints);
        }

        parts.Add("Style: photorealistic or artistic illustration, widescreen landscape orientation, no text overlay.");

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
