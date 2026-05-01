using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace WondayWall.Services;

public class ToolDownloadService(IHttpClientFactory httpClientFactory, ILogger<ToolDownloadService> logger)
{
    private const string RealEsrganDownloadUrl =
        "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip";

    private static readonly string ToolsDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "WondayWall", "tools");

    private static readonly string RealEsrganDirectory = Path.Combine(ToolsDirectory, "realesrgan-ncnn-vulkan");

    public async Task<RealEsrganToolInfo?> EnsureRealEsrganAsync(CancellationToken ct = default)
    {
        if (!OperatingSystem.IsWindows() || RuntimeInformation.ProcessArchitecture != Architecture.X64)
        {
            logger.LogInformation("Real-ESRGAN-ncnn-vulkan は Windows x64 以外では使用しません");
            return null;
        }

        var existing = FindRealEsrganTool();
        if (existing is not null)
            return existing;

        try
        {
            await DownloadAndExtractRealEsrganAsync(ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Real-ESRGAN-ncnn-vulkan の取得に失敗しました。Lanczos にフォールバックします");
            return null;
        }

        var installed = FindRealEsrganTool();
        if (installed is null)
            logger.LogWarning("Real-ESRGAN-ncnn-vulkan の exe または models フォルダーが見つかりません。Lanczos にフォールバックします");

        return installed;
    }

    private async Task DownloadAndExtractRealEsrganAsync(CancellationToken ct)
    {
        Directory.CreateDirectory(RealEsrganDirectory);

        var zipPath = Path.Combine(RealEsrganDirectory, "realesrgan-ncnn-vulkan-windows.zip");
        var tempZipPath = $"{zipPath}.tmp";

        var httpClient = httpClientFactory.CreateClient("WondayWall.Tools");
        using var response = await httpClient.GetAsync(RealEsrganDownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();

        await using (var zipStream = File.Create(tempZipPath))
        {
            await response.Content.CopyToAsync(zipStream, ct);
        }

        if (File.Exists(zipPath))
            File.Delete(zipPath);
        File.Move(tempZipPath, zipPath);

        ZipFile.ExtractToDirectory(zipPath, RealEsrganDirectory, overwriteFiles: true);
    }

    private static RealEsrganToolInfo? FindRealEsrganTool()
    {
        if (!Directory.Exists(RealEsrganDirectory))
            return null;

        var exePath = Directory
            .EnumerateFiles(RealEsrganDirectory, "realesrgan-ncnn-vulkan.exe", SearchOption.AllDirectories)
            .FirstOrDefault();
        if (exePath is null)
            return null;

        var workingDirectory = Path.GetDirectoryName(exePath);
        if (string.IsNullOrEmpty(workingDirectory))
            return null;

        var modelsDirectory = Path.Combine(workingDirectory, "models");
        if (!Directory.Exists(modelsDirectory))
            return null;

        return new RealEsrganToolInfo(exePath, workingDirectory, modelsDirectory);
    }
}

public sealed record RealEsrganToolInfo(
    string ExecutablePath,
    string WorkingDirectory,
    string ModelsDirectory);
