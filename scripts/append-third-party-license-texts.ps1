param(
    [Parameter(Mandatory = $true)]
    [string]$NoticesPath,

    [Parameter(Mandatory = $true)]
    [string]$LicenseFilesDirectory,

    [string]$NuGetPackagesDirectory = $env:NUGET_PACKAGES,

    [string]$OverridePackageInformationPath = "eng\licenses\package-overrides.json",

    [string]$RepositoryRoot = (Resolve-Path ".").Path
)

$ErrorActionPreference = "Stop"

function Get-RelativePath([string]$BasePath, [string]$Path) {
    $baseUri = [Uri]((Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\') + '\')
    $pathUri = [Uri](Resolve-Path -LiteralPath $Path).Path
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Read-TextFile([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }

    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Add-NoticeSection(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Title,
    [string]$Source,
    [string]$Content
) {
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return
    }

    $Lines.Add("")
    $Lines.Add("### $Title")
    $Lines.Add("")
    $Lines.Add("Source: ``$Source``")
    $Lines.Add("")
    $Lines.Add("````text")
    $Lines.Add($Content.TrimEnd())
    $Lines.Add("````")
}

function Get-RestoredPackages([string]$Root) {
    $packages = [ordered]@{}

    Get-ChildItem -LiteralPath $Root -Filter project.assets.json -Recurse |
        Where-Object { $_.FullName -match '\\obj\\project\.assets\.json$' } |
        ForEach-Object {
            $assets = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            if ($null -eq $assets.libraries) {
                return
            }

            foreach ($library in $assets.libraries.PSObject.Properties) {
                if ($library.Value.type -ne "package") {
                    continue
                }

                $separatorIndex = $library.Name.LastIndexOf('/')
                if ($separatorIndex -lt 1) {
                    continue
                }

                $id = $library.Name.Substring(0, $separatorIndex)
                $version = $library.Name.Substring($separatorIndex + 1)
                $key = "$($id.ToLowerInvariant())/$version"
                $packages[$key] = [pscustomobject]@{
                    Id = $id
                    Version = $version
                }
            }
        }

    return $packages.Values
}

function Test-LicenseRelatedFile([System.IO.FileInfo]$File) {
    if ($File.Length -eq 0 -or $File.Length -gt 1MB) {
        return $false
    }

    $name = $File.Name
    $extension = $File.Extension.ToLowerInvariant()
    $textExtensions = @("", ".txt", ".md", ".markdown", ".rst", ".html", ".htm", ".rtf")

    if ($textExtensions -notcontains $extension) {
        return $false
    }

    return $name -match '(?i)(^|[-_. ])(license|licence|notice|copying|third[-_. ]party[-_. ]notice)'
}

$resolvedNoticesPath = Resolve-Path -LiteralPath $NoticesPath
$noticesContent = Get-Content -LiteralPath $resolvedNoticesPath -Raw
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add($noticesContent.TrimEnd())
$lines.Add("")
$lines.Add("## License Texts and Notices")
$lines.Add("")
$lines.Add("This section includes license files downloaded by nuget-license and license/NOTICE files found in restored NuGet packages.")

$addedSources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$packagesWithLocalLicenseFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if (Test-Path -LiteralPath $LicenseFilesDirectory) {
    Get-ChildItem -LiteralPath $LicenseFilesDirectory -File -Recurse |
        Sort-Object FullName |
        ForEach-Object {
            $source = Get-RelativePath -BasePath $RepositoryRoot -Path $_.FullName
            if ($addedSources.Add($source)) {
                Add-NoticeSection -Lines $lines -Title "Downloaded license file: $source" -Source $source -Content (Read-TextFile -Path $_.FullName)
            }
        }
}

if (-not [string]::IsNullOrWhiteSpace($NuGetPackagesDirectory) -and (Test-Path -LiteralPath $NuGetPackagesDirectory)) {
    foreach ($package in Get-RestoredPackages -Root $RepositoryRoot) {
        $packageKey = "$($package.Id)/$($package.Version)"
        $packageDirectory = Join-Path $NuGetPackagesDirectory (Join-Path $package.Id.ToLowerInvariant() $package.Version)
        if (-not (Test-Path -LiteralPath $packageDirectory)) {
            continue
        }

        Get-ChildItem -LiteralPath $packageDirectory -File -Recurse |
            Where-Object { Test-LicenseRelatedFile -File $_ } |
            Sort-Object FullName |
            ForEach-Object {
                $source = Get-RelativePath -BasePath $RepositoryRoot -Path $_.FullName
                if ($addedSources.Add($source)) {
                    [void]$packagesWithLocalLicenseFiles.Add($packageKey)
                    Add-NoticeSection -Lines $lines -Title "$($package.Id) $($package.Version): $($_.Name)" -Source $source -Content (Read-TextFile -Path $_.FullName)
                }
            }
    }
}

if (Test-Path -LiteralPath $OverridePackageInformationPath) {
    $overrides = Get-Content -LiteralPath $OverridePackageInformationPath -Raw | ConvertFrom-Json
    foreach ($override in $overrides) {
        if ([string]::IsNullOrWhiteSpace($override.LicenseUrl)) {
            continue
        }

        $packageKey = "$($override.Id)/$($override.Version)"
        if ($packagesWithLocalLicenseFiles.Contains($packageKey)) {
            continue
        }

        $source = $override.LicenseUrl
        if ($addedSources.Add($source)) {
            $content = (Invoke-WebRequest -Uri $override.LicenseUrl -UseBasicParsing).Content
            Add-NoticeSection -Lines $lines -Title "$($override.Id) $($override.Version): override license URL" -Source $source -Content $content
        }
    }
}

if ($addedSources.Count -eq 0) {
    throw "No license text or NOTICE files were found."
}

Set-Content -LiteralPath $resolvedNoticesPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
