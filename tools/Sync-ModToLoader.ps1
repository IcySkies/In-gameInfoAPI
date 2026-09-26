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

if (Test-Path -LiteralPath $legacyRoot) {
    throw "Legacy loader mirror still exists: $legacyRoot. Rename or remove it before syncing."
}

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
$sourceFiles = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch "\\\.git\\" -and
    $_.FullName -notmatch "\\tools\\" -and
    $_.Name -ne "AGENTS.md"
}
$sourceRelative = @{}
foreach ($file in $sourceFiles) {
    $relative = $file.FullName.Substring($sourceRoot.Length + 1)
    $sourceRelative[$relative] = $true
    $destination = Join-Path $targetRoot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
}

$markerPath = Join-Path $targetRoot $markerName
Set-Content -LiteralPath $markerPath -Encoding UTF8 -Value @(
    "Generated deployment mirror. Do not edit this directory directly."
    "Authoritative source: $sourceRoot"
    "Installed package: $targetName"
)

Get-ChildItem -LiteralPath $targetRoot -Recurse -File | Where-Object {
    $_.Name -ne $markerName
} | ForEach-Object {
    $relative = $_.FullName.Substring($targetRoot.Length + 1)
    if (-not $sourceRelative.ContainsKey($relative)) {
        Remove-Item -LiteralPath $_.FullName -Force
    }
}

Write-Output "Synchronized $($sourceFiles.Count) source files to $targetRoot"
