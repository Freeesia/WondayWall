using System.Diagnostics;
using System.IO;
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
        string requestedMode,
        CancellationToken ct = default)
    {
        var normalizedMode = UpscaleModeValues.Normalize(requestedMode);
        if (normalizedMode == UpscaleModeValues.Lanczos)
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

        using var process = new Process
        {
            StartInfo = new()
            {
                FileName = tool.ExecutablePath,
                WorkingDirectory = tool.WorkingDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
        };

        var args = process.StartInfo.ArgumentList;
        args.Add("-i");
        args.Add(inputPath);
        args.Add("-o");
        args.Add(outputPath);
        args.Add("-s");
        args.Add("2");
        args.Add("-n");
        args.Add("realesrgan-x4plus");
        args.Add("-m");
        args.Add(tool.ModelsDirectory);
        args.Add("-f");
        args.Add("png");

        process.Start();
        var stdoutTask = process.StandardOutput.ReadToEndAsync(timeoutCts.Token);
        var stderrTask = process.StandardError.ReadToEndAsync(timeoutCts.Token);

        try
        {
            await process.WaitForExitAsync(timeoutCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            TryKill(process);
            throw new InvalidOperationException("Real-ESRGAN-ncnn-vulkan の実行がタイムアウトしました。");
        }

        var stdout = await stdoutTask;
        var stderr = await stderrTask;
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"Real-ESRGAN-ncnn-vulkan が終了コード {process.ExitCode} で失敗しました。{stderr}{stdout}");
        }

        if (!File.Exists(outputPath))
            throw new FileNotFoundException("Real-ESRGAN-ncnn-vulkan の出力画像が見つかりません。", outputPath);

        using var image = await Image.LoadAsync(outputPath, ct);
        return new(outputPath, UpscaleModeValues.RealESRGAN);
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

        return new(outputPath, UpscaleModeValues.Lanczos);
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

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
                process.Kill(entireProcessTree: true);
        }
        catch
        {
            // タイムアウト時の後片付け失敗はフォールバック判定に影響させない。
        }
    }
}

public sealed record UpscaleResult(string FilePath, string ActualMethod);
