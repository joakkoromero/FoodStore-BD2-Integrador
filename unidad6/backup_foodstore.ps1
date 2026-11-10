#requires -Version 7.5
# Base: OpenCode real u6_generacion; integracion/revision Codex documentada en docs/ia/.
[CmdletBinding()]
param(
    [string]$HostName = '127.0.0.1',
    [int]$Port = 55605,
    [Parameter(Mandatory)][string]$DbUser,
    [Parameter(Mandatory)][string]$PgBin,
    [Parameter(Mandatory)][string]$WorkDir,
    [switch]$ConfirmNoWrites
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$env:PGCONNECT_TIMEOUT = '10'
$env:PGAPPNAME = 'u6_backup'
$log = $null; $phase = 'preflight'
. (Join-Path $PSScriptRoot 'tools/ps_common.ps1')
try {
    if ($HostName -ne '127.0.0.1' -or ($Port -lt 1 -or $Port -gt 65535) -or
        -not $ConfirmNoWrites) { throw 'Endpoint o ventana sin escrituras no confirmados.' }
    $WorkDir = (Get-Item -LiteralPath $WorkDir).FullName
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
        throw 'WorkDir no es directorio.'
    }
    Assert-Private $WorkDir
    $BackupDir=Join-Path $WorkDir 'backups'; $LogDir=Join-Path $WorkDir 'logs'
    foreach ($directory in @($BackupDir,$LogDir)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        Assert-Private $directory
    }
    $token = New-RunToken
    $stem = "foodstore_$token"
    $log = New-Writer (Join-Path $LogDir "$stem.log"); $log.AutoFlush = $true
    Log 'START backup'
    if (-not $env:PGPASSFILE -or
        -not (Test-Path -LiteralPath $env:PGPASSFILE -PathType Leaf)) { throw 'Falta PGPASSFILE.' }
    Assert-Private $env:PGPASSFILE
    Assert-Clients @('psql','pg_dump','pg_restore')
    $sql = Join-Path $PSScriptRoot 'validaciones.sql'
    if (-not (Test-Path -LiteralPath $sql -PathType Leaf)) { throw 'Falta validaciones.sql.' }
    $conn = @('-h', $HostName, '-p', "$Port", '-U', $DbUser, '-w')
    $psql = @('-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1') + $conn + @('-d', 'foodstore')
    $check = @'
SELECT (current_setting('server_version_num')::int BETWEEN 170000 AND 179999
 AND (SELECT rolsuper FROM pg_roles WHERE rolname=current_user))::int;
'@
    if ((Pg 'psql' ($psql + @('-c',$check)) | Out-String).Trim() -ne '1') {
        throw 'Se requiere servidor 17 y administrador bootstrap.'
    }
    $phase = 'baseline anterior'
    $baseline = (Pg 'psql' ($psql + @('-f', $sql)) | Out-String) | ConvertFrom-Json -AsHashtable
    Assert-Baseline $baseline
    $partial = Join-Path $BackupDir "$stem.partial"; $dump = Join-Path $BackupDir "$stem.dump"
    if ((Test-Path -LiteralPath $partial) -or (Test-Path -LiteralPath $dump)) { throw 'Colision de nombres.' }
    $phase = 'pg_dump'
    $started = [DateTimeOffset]::UtcNow
    Pg 'pg_dump' ($conn + @('-d', 'foodstore', '-Fc', '-f', $partial)) | Out-Null
    if ((Get-Item -LiteralPath $partial).Length -le 0) { throw 'Respaldo vacio.' }
    $phase = 'TOC y segunda baseline'
    Pg 'pg_restore' @('--list', $partial) | Out-Null
    $after = (Pg 'psql' ($psql + @('-f', $sql)) | Out-String) | ConvertFrom-Json -AsHashtable
    Assert-Baseline $after
    foreach ($section in @('counts','fingerprints','invalid')) {
        foreach ($key in $baseline[$section].Keys) {
            if ($baseline[$section][$key] -cne $after[$section][$key]) { throw 'Cambio observable durante el respaldo.' }
        }
    }
    $size = (Get-Item -LiteralPath $partial).Length
    $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
    $phase = 'publicacion'
    [IO.File]::Move($partial, $dump)
    $ended = [DateTimeOffset]::UtcNow
    $manifest = [ordered]@{
        status='SUCCESS'; database='foodstore'; file="$stem.dump"; size=$size; sha256=$hash
        startUtc=$started.ToString('o'); endUtc=$ended.ToString('o'); baseline=$baseline
        startUtcMinus03=$started.ToOffset([TimeSpan]::FromHours(-3)).ToString('o')
        endUtcMinus03=$ended.ToOffset([TimeSpan]::FromHours(-3)).ToString('o')
    }
    $manifestPartial = Join-Path $LogDir "$stem.manifest.partial"
    $writer = New-Writer $manifestPartial
    try { $writer.Write(($manifest | ConvertTo-Json -Depth 8)) } finally { $writer.Dispose() }
    [IO.File]::Move($manifestPartial, (Join-Path $LogDir "$stem.manifest.json"))
    Log "SUCCESS backup archivo=$stem.dump bytes=$size sha256=$hash"
} catch {
    Log "FAILED backup fase=$phase"
    exit 1
} finally {
    if ($null -ne $log) { $log.Dispose() }
}
exit 0
