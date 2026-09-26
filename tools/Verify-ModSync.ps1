[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\")).Path.TrimEnd('\')
$loaderRoot = (Resolve-Path (Join-Path $sourceRoot "..\SourceFiles\VividStasisModLoader\")).Path.TrimEnd('\')
$targetName = "VividStasisGameInfoAPI v3.0.0"
$legacyName = "AutoChartSwitch Game Bridge v2.0.0"
$targetRoot = Join-Path $loaderRoot ("mods\" + $targetName)
$legacyRoot = Join-Path $loaderRoot ("mods\" + $legacyName)
$markerName = ".in-gameinfoapi-source"

if (Test-Path -LiteralPath $legacyRoot) { throw "Legacy loader mirror exists: $legacyRoot" }
if (-not (Test-Path -LiteralPath $targetRoot)) { throw "Loader mirror is missing: $targetRoot" }

function Get-Manifest($root) {
    $manifest = @{}
    Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($root.Length + 1)
        if ($relative -eq "AGENTS.md" -or $relative.StartsWith("tools\") -or $_.Name -eq $markerName) { return }
        $manifest[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    return $manifest
}

$sourceManifest = Get-Manifest $sourceRoot
$targetManifest = Get-Manifest $targetRoot
$differences = @(
    Compare-Object ($sourceManifest.Keys | Sort-Object) ($targetManifest.Keys | Sort-Object) -PassThru
    foreach ($path in $sourceManifest.Keys) {
        if ($targetManifest.ContainsKey($path) -and $sourceManifest[$path] -ne $targetManifest[$path]) { $path }
    }
)
if ($differences.Count -gt 0) {
    throw "Loader mirror differs from In-gameInfoAPI: $($differences -join ', ')"
}

$marker = Get-Content -LiteralPath (Join-Path $targetRoot $markerName) -Raw
if ($marker -notmatch [regex]::Escape($sourceRoot)) { throw "Mirror marker does not identify In-gameInfoAPI as its source." }
Write-Output "Verified $($sourceManifest.Count) files; loader mirror is synchronized."
