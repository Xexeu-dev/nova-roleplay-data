param(
    [Parameter(Mandatory = $true)]
    [string]$InputZip
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$assetDirectory = Join-Path $repoRoot "release-assets"
$assetName = "nova-data-base-v1.zip"
$assetPath = Join-Path $assetDirectory $assetName
$manifestPath = Join-Path $repoRoot "manifest.json"
$releaseUrl = "https://github.com/Xexeu-dev/nova-roleplay-data/releases/download/data-v1/$assetName"
$resolvedInput = (Resolve-Path -LiteralPath $InputZip).Path

New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null
Copy-Item -LiteralPath $resolvedInput -Destination $assetPath -Force

function Get-Sha256Hex([System.IO.Stream]$Stream) {
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace("-", "").ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Convert-DataPath([string]$Path) {
    $normalized = $Path.Replace("\", "/").TrimStart("/")
    if ($normalized.StartsWith("files/", [StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(6)
    }
    return $normalized
}

function Test-MutablePath([string]$Path) {
    $lower = $Path.ToLowerInvariant()
    return $lower -eq "samp/log.txt" -or
        $lower -eq "samp/crash_log.txt" -or
        $lower -eq "samp/settings.ini" -or
        $lower -eq "samp/settings.json" -or
        $lower -eq "samp/favorites.json" -or
        $lower.EndsWith("gta_sa.set") -or
        $lower.EndsWith("gtasatelem.set") -or
        $lower.EndsWith("stream.ini") -or
        $lower.StartsWith("scache")
}

$filesByPath = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
$archive = [System.IO.Compression.ZipFile]::OpenRead($assetPath)
try {
    foreach ($entry in $archive.Entries) {
        if ([string]::IsNullOrEmpty($entry.Name)) { continue }
        $path = Convert-DataPath $entry.FullName
        if ([string]::IsNullOrWhiteSpace($path) -or (Test-MutablePath $path)) { continue }
        $stream = $entry.Open()
        try {
            $hash = Get-Sha256Hex $stream
        } finally {
            $stream.Dispose()
        }
        $filesByPath[$path] = [ordered]@{
            path = $path
            sizeBytes = [long]$entry.Length
            sha256 = $hash
        }
    }
} finally {
    $archive.Dispose()
}

$assetStream = [System.IO.File]::OpenRead($assetPath)
try {
    $assetHash = Get-Sha256Hex $assetStream
} finally {
    $assetStream.Dispose()
}

$files = @($filesByPath.Values | Sort-Object { $_.path })
$manifest = [ordered]@{
    schemaVersion = 1
    dataVersion = 1
    updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    requiredRoots = @("SAMP", "texdb", "models")
    legacyMarkers = @("NOVA_DATA_1_7_DEFAULT_GTA_SA_ANIMS")
    base = [ordered]@{
        version = 1
        url = $releaseUrl
        sha256 = $assetHash
        sizeBytes = [long](Get-Item -LiteralPath $assetPath).Length
    }
    patches = @()
    files = $files
}

$json = $manifest | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $manifestPath -Value $json -Encoding UTF8

Write-Host "Base pronta: $assetPath"
Write-Host "Manifesto: $manifestPath"
Write-Host "Arquivos gerenciados: $($files.Count)"
Write-Host "SHA-256 da base: $assetHash"
