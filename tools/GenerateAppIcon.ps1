# WondayWall 用の multi-size ICO を PNG 原稿から生成する。
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $projectRoot "assets"
$assetsDir = Join-Path $projectRoot "WondayWall\Assets"
$iconPath = Join-Path $assetsDir "AppIcon.ico"
$smallSourcePath = Join-Path $sourceDir "icon_64.png"
$largeSourcePath = Join-Path $sourceDir "icon_512.png"
$sizes = @(16, 24, 32, 48, 256)

foreach ($path in @($smallSourcePath, $largeSourcePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Source image not found: $path"
    }
}

New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null

function New-ResizedPngBytes {
    param(
        [System.Drawing.Image]$SourceImage,
        [int]$Size
    )

    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.DrawImage($SourceImage, 0, 0, $Size, $Size)

        $stream = [System.IO.MemoryStream]::new()
        try {
            $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
            return $stream.ToArray()
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$smallSource = [System.Drawing.Image]::FromFile($smallSourcePath)
$largeSource = [System.Drawing.Image]::FromFile($largeSourcePath)

try {
    $imageEntries = foreach ($size in $sizes) {
        $source = if ($size -le 32) { $smallSource } else { $largeSource }
        [PSCustomObject]@{
            Size = $size
            Bytes = [byte[]](New-ResizedPngBytes -SourceImage $source -Size $size)
        }
    }

    $fileStream = [System.IO.File]::Create($iconPath)
    $writer = [System.IO.BinaryWriter]::new($fileStream)

    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$imageEntries.Count)

        $offset = 6 + (16 * $imageEntries.Count)
        foreach ($entry in $imageEntries) {
            $writer.Write([byte]($(if ($entry.Size -ge 256) { 0 } else { $entry.Size })))
            $writer.Write([byte]($(if ($entry.Size -ge 256) { 0 } else { $entry.Size })))
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]([byte[]]$entry.Bytes).Length)
            $writer.Write([UInt32]$offset)
            $offset += ([byte[]]$entry.Bytes).Length
        }

        foreach ($entry in $imageEntries) {
            $writer.Write([byte[]]$entry.Bytes)
        }
    }
    finally {
        $writer.Dispose()
        $fileStream.Dispose()
    }
}
finally {
    $smallSource.Dispose()
    $largeSource.Dispose()
}

Write-Output "Generated $iconPath"
