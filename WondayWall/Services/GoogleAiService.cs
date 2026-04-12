using System.IO;
using System.Net.Http;
using GenerativeAI;
using GenerativeAI.Types;
using Microsoft.Extensions.Logging;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GoogleAiService(AppConfigService configService, HttpClient httpClient, ILogger<GoogleAiService> logger)
{
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

        // OGP画像がある場合はインラインデータとして添付
        var parts = new List<Part> { new Part(imagePrompt) };
        foreach (var imgUrl in context.OgpImageUrls.Take(3))
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

        return new GeneratedImageInfo
        {
            FilePath = filePath,
            GeneratedAt = DateTimeOffset.UtcNow,
            UsedPrompt = imagePrompt,
            SourceContext = context,
        };
    }

    /// <summary>
    /// テキストモデルへ送るプロンプトを構築する。
    /// テキストモデルはこのプロンプトを受け取り、画像生成モデル向けの詳細なプロンプトを返す。
    /// </summary>
    private static string BuildTextModelPrompt(PromptContext context)
    {
        var parts = new List<string>
        {
            $"あなたはデスクトップ壁紙の画像生成プロンプト専門家です。" +
            $"以下のコンテキスト情報をもとに、画像生成モデル（{context.ImageSize}解像度、{context.AspectRatio}アスペクト比）向けの" +
            $"詳細で創造的な英語プロンプトを作成してください。" +
            "プロンプトには視覚的要素・スタイル・雰囲気・構図を具体的に記述し、テキストオーバーレイなし・横向きワイドスクリーンを考慮してください。",
        };

        if (!string.IsNullOrWhiteSpace(context.EventSummary) &&
            context.EventSummary != "No upcoming calendar events.")
        {
            parts.Add($"直近の予定:\n{context.EventSummary}");
        }

        if (!string.IsNullOrWhiteSpace(context.NewsSummary) &&
            context.NewsSummary != "No relevant news topics.")
        {
            parts.Add($"現在のニューストピック:\n{context.NewsSummary}");
        }

        if (context.AtmosphereKeywords.Count > 0)
        {
            parts.Add($"興味・雰囲気のキーワード: {string.Join(", ", context.AtmosphereKeywords)}");
        }

        if (!string.IsNullOrWhiteSpace(context.AdditionalConstraints))
        {
            parts.Add($"追加の指示: {context.AdditionalConstraints}");
        }

        parts.Add("画像生成プロンプトのみを出力してください。説明や前置きは不要です。");

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
