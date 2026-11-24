# Gera Tibia74-Local.exe na raiz do repositório com o compilador C# que vem no Windows.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw 'csc.exe do .NET Framework 4 não encontrado.' }
$icon = Join-Path $PSScriptRoot 'tibia74.ico'
$output = Join-Path $repo 'Tibia74-Local.exe'
& $csc /nologo /target:exe /platform:anycpu /optimize+ /codepage:65001 "/win32icon:$icon" "/out:$output" (Join-Path $PSScriptRoot 'Tibia74Local.cs')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar.' }
Write-Host "OK: $output"
