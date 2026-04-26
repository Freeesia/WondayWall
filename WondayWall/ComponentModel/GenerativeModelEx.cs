using System.Net.Http;
using System.Text.Json.Serialization;
using GenerativeAI;
using GenerativeAI.Types;
using Microsoft.Extensions.Logging;
using WondayWall.Models;

namespace WondayWall.ComponentModel;

internal class GenerativeModelEx(
    string apiKey,
    string? model,
    GenerationConfig? config = null,
    ICollection<SafetySetting>? safetySettings = null,
    string? systemInstruction = null,
    HttpClient? httpClient = null,
    ILogger? logger = null,
    GoogleAiServiceTier serviceTier = GoogleAiServiceTier.Standard)
    : GenerativeModel(apiKey, model, config, safetySettings, systemInstruction, httpClient, logger)
{
    protected override void ValidateGenerateContentRequest(GenerateContentRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (CachedContent != null && (UseGrounding || UseGoogleSearch || UseCodeExecutionTool))
            throw new NotSupportedException(
                "Cached content mode does not support the use of grounding, Google Search, or code execution tools. Please disable these features.");
    }

    public override async Task<GenerateContentResponse> GenerateContentAsync(
        GenerateContentRequest request,
        CancellationToken cancellationToken = default)
    {
        PrepareRequest(request);
        return await CallFunctionAsync(
            request,
            await GenerateContentAsync(Model, request).ConfigureAwait(false),
            cancellationToken)
            .ConfigureAwait(false);
    }

    protected override async Task<GenerateContentResponse> GenerateContentAsync(string model, GenerateContentRequest request)
    {
        if (serviceTier != GoogleAiServiceTier.Flex)
            return await base.GenerateContentAsync(model, request).ConfigureAwait(false);

        var url = $"{Platform.GetBaseUrl()}/{model.ToModelId()}:generateContent";
        var response = await SendAsync<ServiceTierGenerateContentRequest, GenerateContentResponse>(
            url,
            new ServiceTierGenerateContentRequest(request),
            HttpMethod.Post)
            .ConfigureAwait(false);
        CheckBlockedResponse(response, url);
        return response;
    }

    private sealed class ServiceTierGenerateContentRequest : GenerateContentRequest
    {
        public ServiceTierGenerateContentRequest(GenerateContentRequest request)
        {
            Contents = request.Contents;
            Tools = request.Tools;
            ToolConfig = request.ToolConfig;
            SafetySettings = request.SafetySettings;
            SystemInstruction = request.SystemInstruction;
            GenerationConfig = request.GenerationConfig;
            CachedContent = request.CachedContent;
        }

        [JsonPropertyName("service_tier")]
        public string ServiceTier { get; init; } = "flex";
    }
}
