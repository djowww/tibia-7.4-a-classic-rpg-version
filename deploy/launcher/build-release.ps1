param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 1000000)][int]$Version,
    [Parameter(Mandatory = $true)][string]$ClientSource,
    [Parameter(Mandatory = $true)][string]$LauncherExe,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$IncludeLauncherInUpdate
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source = (Resolve-Path $ClientSource).Path
$launcher = (Resolve-Path $LauncherExe).Path
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$stage = Join-Path $output "client-v$Version"
$packageName = "Antigas-7.4-Update-v$Version.zip"
$legacyName = "Antigas-7.4-Client-v$Version.zip"
$bundleName = "Antigas-7.4-Launcher-v$Version.zip"
$packagePath = Join-Path $output $packageName
$legacyPath = Join-Path $output $legacyName
$bundlePath = Join-Path $output $bundleName
$manifestPath = Join-Path $output 'client-release.json'

if (Test-Path $stage) { throw "Staging already exists; choose a new output directory: $stage" }
if ((Test-Path $packagePath) -or (Test-Path $legacyPath) -or (Test-Path $bundlePath)) { throw 'A release ZIP already exists; choose a new output directory.' }
New-Item -ItemType Directory -Force -Path $output,$stage | Out-Null
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $stage -Recurse -Force
# Only the OpenGL client is shipped: drop the DirectX build and its ANGLE runtime.
foreach ($name in @('Antigas_dx.exe', 'libEGL.dll', 'libGLESv2.dll')) {
    Remove-Item -LiteralPath (Join-Path $stage $name) -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -LiteralPath $stage -Filter 'd3dcompiler_*.dll' -File | Remove-Item -Force
# Base-client files nothing loads here: modules without autoload that no load-later
# list names (updater stays off because Services.updater is empty), unreferenced
# images and sounds, and Windows thumbnail caches.
foreach ($relative in @('modules\updater', 'modules\game_market', 'modules\game_cooldown', 'data\images\rawtextures', 'data\sounds\alarm.ogg', 'data\sounds\magnum.ogg')) {
    Remove-Item -LiteralPath (Join-Path $stage $relative) -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -LiteralPath $stage -Filter 'Thumbs.db' -File -Recurse -Force | Remove-Item -Force

$initPath = Join-Path $stage 'init.lua'
$init = [System.IO.File]::ReadAllText($initPath)
$versionPattern = '(?m)^APP_VERSION\s*=\s*\d+'
if (-not [regex]::IsMatch($init, $versionPattern)) { throw 'Could not locate APP_VERSION in init.lua.' }
$updatedInit = [regex]::Replace($init, $versionPattern, "APP_VERSION = $Version", 1)
[System.IO.File]::WriteAllText($initPath, $updatedInit, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $stage 'client.version'), "$Version`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $stage 'LEIA-ME.txt'), ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'CLIENT-README.txt')).Replace('{{VERSION}}', "$Version")), [System.Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $launcher -Destination (Join-Path $stage 'AntigasLauncher.exe')

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Write-ClientZip([string]$Target, [bool]$IncludeLauncher) {
    $archive = [System.IO.Compression.ZipFile]::Open($Target, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse) {
            if (-not $IncludeLauncher -and $file.Name -eq 'AntigasLauncher.exe') { continue }
            $relative = $file.FullName.Substring($stage.Length).TrimStart('\').Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $file.FullName, $relative, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
    finally { $archive.Dispose() }
}

# Ship a new launcher inside the signed update when its executable has changed.
# Existing launchers preserve their executable only if the package omits it.
Write-ClientZip $packagePath $IncludeLauncherInUpdate.IsPresent
Write-ClientZip $bundlePath $true
Copy-Item -LiteralPath $bundlePath -Destination $legacyPath
$signer = Join-Path $repo 'tools\ReleaseSigner\ReleaseSigner.csproj'
& dotnet run --project $signer -- sign $Version $packagePath $packageName $manifestPath
if ($LASTEXITCODE -ne 0) { throw 'Release signing failed.' }
Write-Output "Update package: $packagePath"
Write-Output "Legacy client download: $legacyPath"
Write-Output "Launcher bundle: $bundlePath"
Write-Output "Signed manifest: $manifestPath"
