<#
.SYNOPSIS
  Convert an MSI / EXE installer to MSIX using Microsoft MSIX Packaging Tool CLI.

.DESCRIPTION
  This is a release helper for producing an MSIX package from an existing installer.

  Recommended usage:
    1. Create one conversion template from the MSIX Packaging Tool UI.
    2. Replace environment-specific values in that template with the placeholders below.
    3. Run this script in an elevated PowerShell session on a clean packaging VM.

  Supported placeholders in -TemplatePath:
    {{InstallerPath}}
    {{InstallerArguments}}
    {{InstallLocation}}
    {{PackageName}}
    {{PackageDisplayName}}
    {{PublisherName}}
    {{PublisherDisplayName}}
    {{PackageVersion}}
    {{Architecture}}
    {{OutputPackagePath}}
    {{GeneratedTemplatePath}}

.NOTES
  Requirements:
    - Windows 10 / 11
    - Microsoft MSIX Packaging Tool
    - Administrator PowerShell
    - Clean packaging environment strongly recommended

  Microsoft Store submission usually requires additional Store Partner Center packaging
  and identity/signing validation. Treat this as an MSIX generation step, not the whole
  Store release process.

.EXAMPLE
  .\scripts\convert-msi-to-msix.ps1 `
    -InstallerPath .\artifacts\installer\WondayWall.msi `
    -PackageName WondayWall `
    -PackageDisplayName WondayWall `
    -PublisherName "CN=Freeesia" `
    -PublisherDisplayName "Freeesia" `
    -PackageVersion "0.1.0.0" `
    -OutputDirectory .\artifacts\msix

.EXAMPLE
  .\scripts\convert-msi-to-msix.ps1 `
    -InstallerPath .\artifacts\installer\WondayWall.msi `
    -TemplatePath .\packaging\msix-template.xml `
    -PackageName WondayWall `
    -PublisherName "CN=Freeesia" `
    -PackageVersion "0.1.0.0" `
    -OutputDirectory .\artifacts\msix
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$InstallerPath,

    [string]$InstallerArguments = "/qn /norestart",

    [string]$InstallLocation,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$PackageName,

    [string]$PackageDisplayName,

    [Parameter(Mandatory = $true)]
    [string]$PublisherName,

    [string]$PublisherDisplayName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$PackageVersion,

    [ValidateSet('x86', 'x64', 'arm64', 'neutral')]
    [string]$Architecture = 'x64',

    [string]$OutputDirectory = '.\artifacts\msix',

    [string]$OutputPackageName,

    [string]$TemplatePath,

    [string]$MsixPackagingToolPath,

    [switch]$GenerateTemplateOnly,

    [switch]$Sign,

    [string]$CertificatePath,

    [securestring]$CertificatePassword,

    [string]$SignToolPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FilePath([string]$Path) {
    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-DirectoryPath([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Executable {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [string[]]$CandidatePaths = @()
    )

    foreach ($candidatePath in $CandidatePaths) {
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidatePath).Path
        }
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    return $null
}

function Find-MsixPackagingTool([string]$ExplicitPath) {
    return Find-Executable -Name 'MsixPackagingTool.exe' -CandidatePaths @(
        $ExplicitPath,
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\MsixPackagingTool.exe')
    )
}

function Find-SignTool([string]$ExplicitPath) {
    $candidates = @($ExplicitPath)
    $windowsKitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'

    if (Test-Path -LiteralPath $windowsKitsRoot) {
        $candidates += Get-ChildItem -LiteralPath $windowsKitsRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' }
    }

    return Find-Executable -Name 'signtool.exe' -CandidatePaths $candidates
}

function ConvertTo-PlainText([securestring]$SecureString) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Escape-Xml([AllowNull()][string]$Value) {
    if ($null -eq $Value) { return '' }
    return [Security.SecurityElement]::Escape($Value)
}

function Expand-TemplatePlaceholders {
    param(
        [Parameter(Mandatory = $true)] [string]$Content,
        [Parameter(Mandatory = $true)] [hashtable]$Values
    )

    $expanded = $Content
    foreach ($key in $Values.Keys) {
        $expanded = $expanded.Replace("{{$key}}", [string]$Values[$key])
    }
    return $expanded
}

function New-StarterTemplate {
    param([hashtable]$Values)

    $installerPath = Escape-Xml $Values.InstallerPath
    $installerArguments = Escape-Xml $Values.InstallerArguments
    $installLocation = Escape-Xml $Values.InstallLocation
    $packageName = Escape-Xml $Values.PackageName
    $packageDisplayName = Escape-Xml $Values.PackageDisplayName
    $publisherName = Escape-Xml $Values.PublisherName
    $publisherDisplayName = Escape-Xml $Values.PublisherDisplayName
    $outputPackagePath = Escape-Xml $Values.OutputPackagePath
    $generatedTemplatePath = Escape-Xml $Values.GeneratedTemplatePath

    $installLocationAttribute = ''
    if (-not [string]::IsNullOrWhiteSpace($installLocation)) {
        $installLocationAttribute = "`n    InstallLocation=\"$installLocation\""
    }

    return @"
<?xml version="1.0" encoding="utf-8"?>
<MsixPackagingToolTemplate
  xmlns="http://schemas.microsoft.com/appx/msixpackagingtool/template/2018">
  <Settings
    AllowTelemetry="true"
    ApplyAllPrepareComputerFixes="true"
    GenerateCommandLineFile="true"
    AllowPromptForPassword="false"
    EnforceMicrosoftStoreVersioningRequirements="true" />
  <SaveLocation
    PackagePath="$outputPackagePath"
    TemplatePath="$generatedTemplatePath" />
  <Installer
    Path="$installerPath"
    Arguments="$installerArguments"$installLocationAttribute />
  <PackageInformation
    PackageName="$packageName"
    PackageDisplayName="$packageDisplayName"
    PublisherName="$publisherName"
    PublisherDisplayName="$publisherDisplayName"
    Version="$($Values.PackageVersion)">
  </PackageInformation>
</MsixPackagingToolTemplate>
"@
}

if (-not $PackageDisplayName) { $PackageDisplayName = $PackageName }
if (-not $PublisherDisplayName) { $PublisherDisplayName = $PublisherName }

$resolvedInstallerPath = Resolve-FilePath $InstallerPath
$resolvedOutputDirectory = Resolve-DirectoryPath $OutputDirectory

if (-not $OutputPackageName) {
    $OutputPackageName = "$PackageName-$PackageVersion.msix"
}

$outputPackagePath = Join-Path $resolvedOutputDirectory $OutputPackageName
$generatedTemplatePath = Join-Path $resolvedOutputDirectory "$PackageName.msix-template.generated.xml"

$templateValues = @{
    InstallerPath         = $resolvedInstallerPath
    InstallerArguments    = $InstallerArguments
    InstallLocation       = $InstallLocation
    PackageName           = $PackageName
    PackageDisplayName    = $PackageDisplayName
    PublisherName         = $PublisherName
    PublisherDisplayName  = $PublisherDisplayName
    PackageVersion        = $PackageVersion
    Architecture          = $Architecture
    OutputPackagePath     = $outputPackagePath
    GeneratedTemplatePath = $generatedTemplatePath
}

if ($TemplatePath) {
    $templateContent = Get-Content -LiteralPath (Resolve-FilePath $TemplatePath) -Raw -Encoding UTF8
    $expandedTemplate = Expand-TemplatePlaceholders -Content $templateContent -Values $templateValues
}
else {
    Write-Warning 'No -TemplatePath was specified. A starter template will be generated. For reliable conversion, export a template from MSIX Packaging Tool UI and pass it with -TemplatePath.'
    $expandedTemplate = New-StarterTemplate -Values $templateValues
}

Set-Content -LiteralPath $generatedTemplatePath -Value $expandedTemplate -Encoding UTF8
Write-Host "Generated template: $generatedTemplatePath"

if ($GenerateTemplateOnly) {
    Write-Host 'Template generation completed.'
    exit 0
}

if (-not (Test-IsAdministrator)) {
    throw 'MSIX conversion requires an elevated PowerShell session. Start PowerShell as Administrator.'
}

$msixPackagingTool = Find-MsixPackagingTool -ExplicitPath $MsixPackagingToolPath
if (-not $msixPackagingTool) {
    throw 'MsixPackagingTool.exe was not found. Install Microsoft MSIX Packaging Tool, or pass -MsixPackagingToolPath.'
}

Write-Host "Using MSIX Packaging Tool: $msixPackagingTool"
Write-Host "Output MSIX: $outputPackagePath"

if ($PSCmdlet.ShouldProcess($resolvedInstallerPath, "Convert to $outputPackagePath")) {
    & $msixPackagingTool create-package --template $generatedTemplatePath -v

    if ($LASTEXITCODE -ne 0) {
        throw "MSIX Packaging Tool failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $outputPackagePath -PathType Leaf)) {
    Write-Warning "Expected MSIX was not found: $outputPackagePath"
    Write-Warning 'Check PackagePath in the generated template and MSIX Packaging Tool logs.'
}

if ($Sign) {
    if (-not $CertificatePath) {
        throw 'Pass -CertificatePath when using -Sign.'
    }

    if (-not (Test-Path -LiteralPath $outputPackagePath -PathType Leaf)) {
        throw "Cannot sign because the MSIX file does not exist: $outputPackagePath"
    }

    $signTool = Find-SignTool -ExplicitPath $SignToolPath
    if (-not $signTool) {
        throw 'signtool.exe was not found. Install Windows SDK, or pass -SignToolPath.'
    }

    $signArgs = @('sign', '/fd', 'SHA256', '/f', (Resolve-FilePath $CertificatePath))
    if ($CertificatePassword) {
        $signArgs += @('/p', (ConvertTo-PlainText $CertificatePassword))
    }
    $signArgs += $outputPackagePath

    & $signTool @signArgs
    if ($LASTEXITCODE -ne 0) {
        throw "SignTool failed with exit code $LASTEXITCODE."
    }
}

Write-Host 'MSIX conversion completed.'
Write-Host "Template: $generatedTemplatePath"
Write-Host "MSIX:     $outputPackagePath"
