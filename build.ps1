<#
.SYNOPSIS
    Build a ListInventory release zip locally, and optionally install it into a WoW AddOns folder.

.DESCRIPTION
    Produces dist\ListInventory-<version>.zip containing a ListInventory\ folder, laid out the same
    way as the zips the BigWigs packager builds in GitHub Actions. Use it to test a build or
    to upload by hand to CurseForge, Wago or WoWInterface.

.EXAMPLE
    .\build.ps1 -Version 1.0.0

.EXAMPLE
    .\build.ps1 -Version 1.0.0-dev -AddOnsPath "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
#>
param(
    # Version written into the TOC in place of @project-version@. Defaults to the latest git tag.
    [string]$Version,
    # When set, the built ListInventory folder is also copied into this AddOns folder.
    [string]$AddOnsPath
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not $Version) {
    $Version = 'dev'
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $tag = git -C $root describe --tags --always 2>$null
        if ($LASTEXITCODE -eq 0 -and $tag) { $Version = $tag.Trim() -replace '^v', '' }
    }
}

# Files that make up the addon. Everything else in the repo stays out of the zip.
$files = @('ListInventory.toc', 'Core.lua', 'Data.lua', 'UI.lua', 'README.md', 'LICENSE')

$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'ListInventory'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

foreach ($f in $files) {
    Copy-Item (Join-Path $root $f) (Join-Path $stage $f)
}

$toc = Join-Path $stage 'ListInventory.toc'
$content = [IO.File]::ReadAllText($toc).Replace('@project-version@', $Version)
[IO.File]::WriteAllText($toc, $content, (New-Object Text.UTF8Encoding $false))

$zip = Join-Path $dist "ListInventory-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
# Entries are added one by one with explicit forward-slash names. Compress-Archive and
# ZipFile.CreateFromDirectory on Windows PowerShell 5.1 write backslash paths, which some
# addon managers and Linux unzip tools mishandle.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $stage $f),
            "ListInventory/$f", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $archive.Dispose()
}
Write-Host "Built $zip"

if ($AddOnsPath) {
    $target = Join-Path $AddOnsPath 'ListInventory'
    New-Item -ItemType Directory -Force $target | Out-Null
    Copy-Item (Join-Path $stage '*') $target -Force
    Write-Host "Installed to $target"
}
