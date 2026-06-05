param(
    [string]$Version
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$addonName = "ChatTabsOrganizer"
$addonDir = Join-Path $repoRoot $addonName
$tocPath = Join-Path $addonDir "$addonName.toc"
$distDir = Join-Path $repoRoot "dist"

if (-not (Test-Path -LiteralPath $tocPath)) {
    throw "Could not find addon TOC at $tocPath"
}

if (-not $Version) {
    $tocVersionLine = Get-Content -LiteralPath $tocPath | Where-Object { $_ -match "^## Version:\s*(.+)$" } | Select-Object -First 1

    if (-not $tocVersionLine) {
        throw "Could not find ## Version in $tocPath"
    }

    $Version = ($tocVersionLine -replace "^## Version:\s*", "").Trim()
}

New-Item -ItemType Directory -Force -Path $distDir | Out-Null

$stagingRoot = Join-Path $distDir "_staging"
$stagingAddon = Join-Path $stagingRoot $addonName
$zipPath = Join-Path $distDir "$addonName-$Version.zip"

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Force -Path $stagingAddon | Out-Null
Copy-Item -LiteralPath (Join-Path $addonDir "$addonName.toc") -Destination $stagingAddon
Copy-Item -LiteralPath (Join-Path $addonDir "Core.lua") -Destination $stagingAddon

Compress-Archive -LiteralPath $stagingAddon -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

Write-Output "Created $zipPath"
