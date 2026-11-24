param([switch]$NoClient, [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
function Invoke-LocalCompose {
    & docker compose @args
    if ($LASTEXITCODE -ne 0) { throw 'Docker failed. Check the message above. Saved data was not deleted.' }
}
function Confirm-DevAccount {
    # Databases created before the dev account existed keep their old rows:
    # the schema only runs on an empty volume. Never changes a password.
    $ErrorActionPreference = 'Continue'
    $sql = @'
DELIMITER //
BEGIN NOT ATOMIC
  IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = 1) THEN
    INSERT INTO accounts (id,password,type,premdays) VALUES (1,SHA1('1'),5,0);
  END IF;
  IF EXISTS (SELECT 1 FROM accounts WHERE id = 1 AND password = SHA1('1')) THEN
    UPDATE accounts SET type = 5 WHERE id = 1;
    IF EXISTS (SELECT 1 FROM players WHERE name = 'Dev') THEN
      UPDATE players SET account_id = 1, group_id = 3 WHERE name = 'Dev';
    ELSE
      INSERT INTO players (name,account_id,group_id,town_id,posx,posy,posz,cap,conditions,comment,sex,looktype)
      VALUES ('Dev',1,3,1,32369,32241,7,400,X'','Local developer character',1,75);
    END IF;
    SELECT 'dev-ok';
  ELSE
    SELECT 'dev-other-password';
  END IF;
END//
'@
    $result = $sql | & docker compose exec -T db mariadb -N -B -ulocalgame -plocalgame tibia_local 2>&1 | Out-String
    if ($result -match 'dev-ok') { return }
    if ($result -match 'dev-other-password') {
        Write-Host 'Warning: account 1 already exists with another password in this saved world; the Dev account (1 / 1) was not created.' -ForegroundColor Yellow
    } else {
        Write-Host ('Warning: could not check the Dev account (1 / 1). ' + $result.Trim()) -ForegroundColor Yellow
    }
}
function Test-Docker {
    $ErrorActionPreference = 'Continue'
    & docker info *> $null
    return ($LASTEXITCODE -eq 0)
}
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Install and open Docker Desktop (Linux containers) first.' }
    if (-not (Test-Docker)) {
        $cli = Split-Path -Parent (Get-Command docker).Source
        $desktop = @(
            (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'),
            (Join-Path $cli '..\..\Docker Desktop.exe')
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($desktop) {
            Write-Host 'Opening Docker Desktop...'
            Start-Process -FilePath $desktop
            for ($i = 0; $i -lt 90 -and -not (Test-Docker); $i++) { Start-Sleep -Seconds 2 }
        }
        if (-not (Test-Docker)) { throw 'Open Docker Desktop and wait for it to finish starting.' }
    }
    Write-Host 'Starting local database and server. The first build takes several minutes.'
    Invoke-LocalCompose up -d --build --wait --wait-timeout 600
    Confirm-DevAccount
    if ($NoClient) { Write-Host 'Server ready. Account: 2 / local123 | Dev (GOD): 1 / 1'; exit 0 }
    $client = Join-Path $PSScriptRoot 'client'
    if (-not (Test-Path -LiteralPath (Join-Path $client '.local-client-complete'))) {
        $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'client-release.json') -Raw | ConvertFrom-Json
        $archive = Join-Path $env:TEMP ('tibia74-local-' + [guid]::NewGuid().ToString('N') + '.zip')
        Write-Host 'Downloading the local test client...'
        Invoke-WebRequest -Uri $manifest.url -OutFile $archive -UseBasicParsing
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $manifest.sha256) { throw 'Client checksum mismatch. Download rejected.' }
        $staging = Join-Path $PSScriptRoot ('.client-install-' + [guid]::NewGuid().ToString('N'))
        Expand-Archive -LiteralPath $archive -DestinationPath $staging
        foreach ($required in @('Antigas_gl.exe', 'init.lua', 'data/things/772/Tibia.dat', 'data/things/772/Tibia.spr', 'modules/client_entergame/entergame.lua')) {
            if (-not (Test-Path -LiteralPath (Join-Path $staging $required))) { throw ('Incomplete client: ' + $required) }
        }
        Set-Content -LiteralPath (Join-Path $staging '.local-client-complete') -Value 'local-v1' -Encoding Ascii
        $localRoot = [IO.Path]::GetFullPath($PSScriptRoot) + [IO.Path]::DirectorySeparatorChar
        foreach ($target in @($client, $staging)) {
            if (-not [IO.Path]::GetFullPath($target).StartsWith($localRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Client path is outside the local workspace.' }
        }
        if (Test-Path -LiteralPath $client) {
            $previous = Join-Path $PSScriptRoot ('.client-incomplete-' + [guid]::NewGuid().ToString('N'))
            Move-Item -LiteralPath $client -Destination $previous
        }
        Move-Item -LiteralPath $staging -Destination $client
    }
    $modulus = (Invoke-LocalCompose exec -T server cat /local-state/public-modulus.txt | Out-String).Trim()
    if ($modulus -notmatch '^\d{308,309}$') { throw 'Could not obtain the local server public key.' }
    $init = Join-Path $client 'init.lua'
    $text = Get-Content -LiteralPath $init -Raw
    $text = [regex]::Replace($text, 'ANTIGAS_RSA_PUBLIC_KEY = "[^"]+"', ('ANTIGAS_RSA_PUBLIC_KEY = "' + $modulus + '"'))
    [IO.File]::WriteAllText($init, $text, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Ready! Account: 2 | Password: local123 | Character: Local Adventurer. Dev (GOD): account 1 | password 1 | character Dev'
    if ($NoLaunch) { exit 0 }
    Start-Process -FilePath (Join-Path $client 'Antigas_gl.exe') -WorkingDirectory $client
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Diagnostics: docker compose logs --tail 60'
    exit 1
}
