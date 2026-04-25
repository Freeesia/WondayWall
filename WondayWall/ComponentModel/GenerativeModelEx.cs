using System.Net.Http;
using GenerativeAI;
using GenerativeAI.Types;
using Microsoft.Extensions.Logging;

namespace WondayWall.ComponentModel;

internal class GenerativeModelEx(string apiKey, string? model, GenerationConfig? config = null, ICollection<SafetySetting>? safetySettings = null, string? systemInstruction = null, HttpClient? httpClient = null, ILogger? logger = null)
    : GenerativeModel(apiKey, model, config, safetySettings, systemInstruction, httpClient, logger)
{
    protected override void ValidateGenerateContentRequest(GenerateContentRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (CachedContent != null && (UseGrounding || UseGoogleSearch || UseCodeExecutionTool))
            throw new NotSupportedException(
                "Cached content mode does not support the use of grounding, Google Search, or code execution tools. Please disable these features.");
    }
}
