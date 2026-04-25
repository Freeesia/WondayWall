namespace WondayWall.Models;

public static class UpscaleModeValues
{
    public const string RealESRGAN = "RealESRGAN";
    public const string Lanczos = "Lanczos";

    public static string Normalize(string? value)
        => value is Lanczos or RealESRGAN ? value : RealESRGAN;
}
