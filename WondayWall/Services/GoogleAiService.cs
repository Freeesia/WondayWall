using System.IO;
using GenerativeAI;
using GenerativeAI.Types;
using WondayWall.Models;
using WondayWall.Utils;

namespace WondayWall.Services;

public class GoogleAiService(AppConfigService configService)
{
    public async Task<GeneratedImageInfo> GenerateWallpaperAsync(
        PromptContext context,
        CancellationToken ct = default)
    {
        var config = configService.Current;

        if (string.IsNullOrWhiteSpace(config.GoogleAiApiKey))
            throw new InvalidOperationException("Google AI API key is not configured.");

        var prompt = BuildPrompt(context);

        var model = new GenerativeModel(config.GoogleAiApiKey, 
            string.IsNullOrWhiteSpace(config.GoogleAiModelName) 
                ? "gemini-2.0-flash-preview-image-generation"
                : config.GoogleAiModelName);
        var response = await model.GenerateContentAsync(prompt, cancellationToken: ct);

        var imageBytes = ExtractImageBytes(response);

        if (imageBytes == null || imageBytes.Length == 0)
            throw new InvalidOperationException("No image data returned from Google AI.");

        var savePath = string.IsNullOrWhiteSpace(config.ImageSavePath)
            ? Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.MyPictures), "WondayWall")
            : config.ImageSavePath;

        var filePath = FileNameHelper.GetImageFilePath(savePath);
        await File.WriteAllBytesAsync(filePath, imageBytes, ct);

        return new GeneratedImageInfo
        {
            FilePath = filePath,
            GeneratedAt = DateTimeOffset.UtcNow,
            UsedPrompt = prompt,
            SourceContext = context,
        };
    }

    private static string BuildPrompt(PromptContext context)
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
