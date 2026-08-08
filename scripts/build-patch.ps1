param(
    [Parameter(Mandatory = $true)]
    [string]$DataDirectory,

    [Parameter(Mandatory = $false)]
    [int]$Version = 0
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$manifestPath = Join-Path $repoRoot "manifest.json"
$assetDirectory = Join-Path $repoRoot "release-assets"
$trimChars = [char[]]@('\', '/')
$sourceRoot = (Resolve-Path -LiteralPath $DataDirectory).Path.TrimEnd($trimChars)

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "manifest.json nao foi encontrado. Gere a base antes do primeiro patch."
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$fromVersion = [int]$manifest.dataVersion
if ($Version -le 0) {
    $Version = $fromVersion + 1
}
if ($Version -ne ($fromVersion + 1)) {
    throw "O patch deve ser sequencial: esperado $($fromVersion + 1), recebido $Version."
}

$tagName = "data-v$Version"
$assetName = "nova-data-patch-v$Version.zip"
$assetPath = Join-Path $assetDirectory $assetName
$releaseUrl = "https://github.com/Xexeu-dev/nova-roleplay-data/releases/download/$tagName/$assetName"
$stagingRoot = Join-Path $repoRoot ".patch-staging-v$Version"

function Get-Sha256Hex([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Convert-DataPath([string]$Path) {
    return $Path.Replace("\", "/").TrimStart([char[]]@('/'))
}

function Test-MutablePath([string]$Path) {
    $lower = $Path.ToLowerInvariant()
    return $lower -eq "xexeu_log.txt" -or
        $lower -eq "samp/log.txt" -or
        $lower -eq "samp/crash_log.txt" -or
        $lower -eq "samp/settings.ini" -or
        $lower -eq "samp/settings.json" -or
        $lower -eq "samp/favorites.json" -or
        $lower.EndsWith("gta_sa.set") -or
        $lower.EndsWith("gtasatelem.set") -or
        $lower.EndsWith("stream.ini") -or
        $lower.StartsWith("scache")
}

$oldFiles = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($item in @($manifest.files)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$item.path)) {
        $oldFiles[[string]$item.path] = $item
    }
}

$newFiles = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
$changedPaths = New-Object 'System.Collections.Generic.List[string]'

foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File) {
    $relative = Convert-DataPath $file.FullName.Substring($sourceRoot.Length).TrimStart($trimChars)
    if ([string]::IsNullOrWhiteSpace($relative) -or (Test-MutablePath $relative)) {
        continue
    }

    $hash = Get-Sha256Hex $file.FullName
    $entry = [ordered]@{
        path = $relative
        sizeBytes = [long]$file.Length
        sha256 = $hash
    }
    $newFiles[$relative] = $entry

    $previous = if ($oldFiles.ContainsKey($relative)) { $oldFiles[$relative] } else { $null }
    if ($null -eq $previous -or
        [long]$previous.sizeBytes -ne [long]$file.Length -or
        [string]$previous.sha256 -ne $hash) {
        $changedPaths.Add($relative)
    }
}

$deletedPaths = New-Object 'System.Collections.Generic.List[string]'
foreach ($oldPath in $oldFiles.Keys) {
    if (-not $newFiles.ContainsKey($oldPath) -and -not (Test-MutablePath $oldPath)) {
        $deletedPaths.Add($oldPath)
    }
}

if ($changedPaths.Count -eq 0 -and $deletedPaths.Count -eq 0) {
    throw "Nenhuma diferenca encontrada entre a pasta informada e o manifesto atual."
}

$resolvedRepoRoot = (Resolve-Path -LiteralPath $repoRoot).Path
if (-not $stagingRoot.StartsWith($resolvedRepoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Diretorio temporario fora do repositorio."
}
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null

try {
    foreach ($relative in $changedPaths) {
        $platformRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $source = Join-Path $sourceRoot $platformRelative
        $destination = Join-Path $stagingRoot $platformRelative
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    if (Test-Path -LiteralPath $assetPath) {
        Remove-Item -LiteralPath $assetPath -Force
    }
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stagingRoot,
        $assetPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
} finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}

$patchHash = Get-Sha256Hex $assetPath
$patch = [ordered]@{
    fromVersion = $fromVersion
    version = $Version
    url = $releaseUrl
    sha256 = $patchHash
    sizeBytes = [long](Get-Item -LiteralPath $assetPath).Length
    deletes = @($deletedPaths | Sort-Object)
}

$updatedManifest = [ordered]@{
    schemaVersion = 1
    dataVersion = $Version
    updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    requiredRoots = @($manifest.requiredRoots)
    legacyMarkers = @($manifest.legacyMarkers)
    base = $manifest.base
    patches = @($manifest.patches) + @($patch)
    files = @($newFiles.Values | Sort-Object { $_.path })
}

$updatedManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Patch pronto: $assetPath"
Write-Host "De data v$fromVersion para v$Version"
Write-Host "Arquivos novos/alterados: $($changedPaths.Count)"
Write-Host "Arquivos removidos: $($deletedPaths.Count)"
Write-Host "SHA-256: $patchHash"
