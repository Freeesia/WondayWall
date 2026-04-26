using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using SixLabors.ImageSharp;
using WondayWall.Services;

if (args.Length == 0)
{
    PrintUsage();
    return 2;
}

if (args[0] is "-h" or "--help")
{
    PrintUsage();
    return 0;
}

var inputPath = ResolveInputPath(args[0]);
if (!File.Exists(inputPath))
{
    Console.Error.WriteLine($"Input image was not found: {inputPath}");
    return 2;
}

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cts.Cancel();
};

await using var serviceProvider = new ServiceCollection()
    .AddLogging(builder =>
    {
        builder
            .SetMinimumLevel(LogLevel.Debug)
            .AddSimpleConsole(options =>
            {
                options.SingleLine = false;
                options.TimestampFormat = "HH:mm:ss ";
            });
    })
    .AddHttpClient("WondayWall.Tools")
    .Services
    .AddSingleton<ToolDownloadService>()
    .AddSingleton<UpscaleService>()
    .BuildServiceProvider();

try
{
    Console.WriteLine($"Input: {inputPath}");

    var upscaleService = serviceProvider.GetRequiredService<UpscaleService>();
    var result = await upscaleService.Upscale2xWithRealEsrganOnlyAsync(inputPath, cts.Token);

    using var inputImage = await Image.LoadAsync(inputPath, cts.Token);
    using var outputImage = await Image.LoadAsync(result.FilePath, cts.Token);

    Console.WriteLine($"Output: {result.FilePath}");
    Console.WriteLine($"Input size: {inputImage.Width}x{inputImage.Height}");
    Console.WriteLine($"Output size: {outputImage.Width}x{outputImage.Height}");
    Console.WriteLine($"Method: {result.ActualMethod}");

    if (outputImage.Width != inputImage.Width * 2 || outputImage.Height != inputImage.Height * 2)
    {
        Console.Error.WriteLine("Real-ESRGAN finished, but the output image is not exactly 2x.");
        return 1;
    }

    Console.WriteLine("Real-ESRGAN 2x upscale succeeded.");
    return 0;
}
catch (OperationCanceledException)
{
    Console.Error.WriteLine("Canceled.");
    return 130;
}
catch (Exception ex)
{
    Console.Error.WriteLine("Real-ESRGAN 2x upscale failed.");
    Console.Error.WriteLine(ex);
    return 1;
}

static void PrintUsage()
{
    Console.WriteLine("Usage:");
    Console.WriteLine("  dotnet run --project WondayWall.RealEsrganCheck -- <input-image-path>");
    Console.WriteLine("  dotnet run --project WondayWall.RealEsrganCheck --launch-profile RealESRGAN-RepoImage");
}

static string ResolveInputPath(string inputPath)
{
    if (Path.IsPathFullyQualified(inputPath))
        return Path.GetFullPath(inputPath);

    var currentDirectoryPath = Path.GetFullPath(inputPath);
    if (File.Exists(currentDirectoryPath))
        return currentDirectoryPath;

    var directory = new DirectoryInfo(AppContext.BaseDirectory);
    while (directory is not null)
    {
        if (File.Exists(Path.Combine(directory.FullName, "WondayWall.RealEsrganCheck.csproj")))
            return Path.GetFullPath(Path.Combine(directory.FullName, inputPath));

        directory = directory.Parent;
    }

    return currentDirectoryPath;
}
