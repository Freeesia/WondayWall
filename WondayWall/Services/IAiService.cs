using WondayWall.Models;

namespace WondayWall.Services;

public interface IAiService
{
    Task<PromptGenerationResult> GeneratePromptAsync(
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        CancellationToken cancellationToken = default);

    Task<PromptContext> FetchOgpImagesAsync(
        PromptContext context,
        IReadOnlyList<string> selectedNewsIds,
        CancellationToken cancellationToken = default);

    Task<GeneratedImageInfo> GenerateImageFromPromptAsync(
        string imagePrompt,
        PromptContext context,
        GoogleAiServiceTier serviceTier,
        CancellationToken cancellationToken = default);
}
