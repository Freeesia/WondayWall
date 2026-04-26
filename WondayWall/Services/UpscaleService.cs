using System.IO;
using Cysharp.Diagnostics;
using Microsoft.Extensions.Logging;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Processing;
using SixLabors.ImageSharp.Processing.Processors.Transforms;
using WondayWall.Models;

namespace WondayWall.Services;

public class UpscaleService(ToolDownloadService toolDownloadService, ILogger<UpscaleService> logger)
{
    private static readonly TimeSpan RealEsrganTimeout = TimeSpan.FromMinutes(10);

    public async Task<UpscaleResult> Upscale2xAsync(
        string inputPath,
        UpscaleMode requestedMode,
        CancellationToken ct = default)
    {
        if (requestedMode == UpscaleMode.Lanczos)
            return await UpscaleWithLanczosAsync(inputPath, ct);

        try
        {
            var tool = await toolDownloadService.EnsureRealEsrganAsync(ct);
            if (tool is not null)
                return await UpscaleWithRealEsrganAsync(inputPath, tool, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Real-ESRGAN-ncnn-vulkan によるアップスケールに失敗しました。Lanczos にフォールバックします");
        }

        return await UpscaleWithLanczosAsync(inputPath, ct);
    }

    private async Task<UpscaleResult> UpscaleWithRealEsrganAsync(
        string inputPath,
        RealEsrganToolInfo tool,
        CancellationToken ct)
    {
        var outputPath = GetUpscaledOutputPath(inputPath, "realesrgan");
        DeleteIfExists(outputPath);

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(RealEsrganTimeout);

        var arguments = $"-i \"{inputPath}\" -o \"{outputPath}\" -s 2 -n realesrgan-x4plus -m \"{tool.ModelsDirectory}\" -f png";

        try
        {
            _ = await ProcessX.StartAsync(tool.ExecutablePath, arguments, tool.WorkingDirectory).ToTask(timeoutCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new InvalidOperationException("Real-ESRGAN-ncnn-vulkan の実行がタイムアウトしました。");
        }
        catch (ProcessErrorException ex)
        {
            throw new InvalidOperationException(
                $"Real-ESRGAN-ncnn-vulkan が終了コード {ex.ExitCode} で失敗しました。{string.Join(Environment.NewLine, ex.ErrorOutput)}",
                ex);
        }

        if (!File.Exists(outputPath))
            throw new FileNotFoundException("Real-ESRGAN-ncnn-vulkan の出力画像が見つかりません。", outputPath);

        using var image = await Image.LoadAsync(outputPath, ct);
        return new(outputPath, UpscaleMode.RealESRGAN);
    }

    private static async Task<UpscaleResult> UpscaleWithLanczosAsync(string inputPath, CancellationToken ct)
    {
        var outputPath = GetUpscaledOutputPath(inputPath, "lanczos");
        DeleteIfExists(outputPath);

        using var image = await Image.LoadAsync(inputPath, ct);
        var width = image.Width * 2;
        var height = image.Height * 2;
        image.Mutate(operation => operation.Resize(width, height, KnownResamplers.Lanczos3));
        await image.SaveAsPngAsync(outputPath, ct);

        return new(outputPath, UpscaleMode.Lanczos);
    }

    private static string GetUpscaledOutputPath(string inputPath, string methodSuffix)
    {
        var directory = Path.GetDirectoryName(inputPath);
        if (string.IsNullOrEmpty(directory))
            directory = Environment.CurrentDirectory;

        var fileName = $"{Path.GetFileNameWithoutExtension(inputPath)}_upscaled_{methodSuffix}.png";
        return Path.Combine(directory, fileName);
    }

    private static void DeleteIfExists(string filePath)
    {
        if (File.Exists(filePath))
            File.Delete(filePath);
    }

}

public sealed record UpscaleResult(string FilePath, UpscaleMode ActualMethod);
