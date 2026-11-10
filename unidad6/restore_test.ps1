#requires -Version 7.5
# Base: OpenCode real u6_generacion; integracion/revision Codex documentada en docs/ia/.
[CmdletBinding()]
param(
    [string]$HostName = '127.0.0.1',
    [int]$Port = 55605,
    [Parameter(Mandatory)][string]$DbUser,
    [Parameter(Mandatory)][string]$PgBin,
    [Parameter(Mandatory)][string]$WorkDir,
    [string[]]$BusinessRoles = @('app_web','admin_datos','rol_app_lectura',
        'rol_app_escritura','rol_soporte','rol_reportes')
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$env:PGCONNECT_TIMEOUT = '10'
$env:PGAPPNAME = 'u6_restore_test'
$log = $null; $timer = $null; $phase = 'preflight'
. (Join-Path $PSScriptRoot 'tools/ps_common.ps1')
try {
    if ($HostName -ne '127.0.0.1' -or ($Port -lt 1 -or $Port -gt 65535)) {
        throw 'Endpoint no permitido.'
    }
    $WorkDir = (Get-Item -LiteralPath $WorkDir).FullName
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
        throw 'WorkDir no es directorio.'
    }
    Assert-Private $WorkDir
    $BackupDir=Join-Path $WorkDir 'backups'; $LogDir=Join-Path $WorkDir 'logs'
    foreach ($directory in @($BackupDir,$LogDir)) { Assert-Private $directory }
    $token = New-RunToken
    $log = New-Writer (Join-Path $LogDir "restore_$token.log"); $log.AutoFlush = $true
    Log 'START restore_test'
    if (-not $env:PGPASSFILE -or
        -not (Test-Path -LiteralPath $env:PGPASSFILE -PathType Leaf)) { throw 'Falta PGPASSFILE.' }
    Assert-Private $env:PGPASSFILE
    Assert-Clients @('psql','createdb','pg_restore')
    $expected = @('app_web','admin_datos','rol_app_lectura',
        'rol_app_escritura','rol_soporte','rol_reportes')
    if (@(Compare-Object ($BusinessRoles | Sort-Object) ($expected | Sort-Object)).Count) {
        throw 'Se requieren los seis roles reales del laboratorio.'
    }
    $roles = ($BusinessRoles | ForEach-Object { '"' + $_.Replace('"','""') + '"' }) -join ', '
    $literals = ($BusinessRoles | ForEach-Object { "'" + $_.Replace("'","''") + "'" }) -join ', '
    $rolesLiteral = "'" + $roles.Replace("'","''") + "'"
    $conn = @('-h', $HostName, '-p', "$Port", '-U', $DbUser, '-w')
    $psql = @('-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1') + $conn
    $checkSql = @"
SELECT json_build_object('version',current_setting('server_version_num')::int,
 'admin',(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),
 'exists',EXISTS(SELECT FROM pg_database WHERE datname='foodstore_restore_test'),
 'roles',(SELECT count(*) FROM pg_roles WHERE rolname IN ($literals)
          AND NOT rolsuper AND rolname<>current_user));
"@
    $check = (Pg 'psql' ($psql + @('-d','postgres','-c',$checkSql)) | Out-String) |
        ConvertFrom-Json -AsHashtable
    if ($check.version -lt 170000 -or $check.version -ge 180000 -or $check.admin -ne $true -or
        $check.exists -ne $false -or $check.roles -ne 6) {
        throw 'Servidor, administrador, destino o roles no validos.'
    }
    $sql = Join-Path $PSScriptRoot 'validaciones.sql'
    if (-not (Test-Path -LiteralPath $sql -PathType Leaf)) { throw 'Falta validaciones.sql.' }
    $chosen = Read-BackupManifest
    $m=$chosen.Manifest; $start=$chosen.Start; $dump=$chosen.Dump
    $dest = $psql + @('-d','foodstore_restore_test')
    $isolation = @'
DO $isolation$
DECLARE n record;
BEGIN
  FOR n IN SELECT nspname FROM pg_namespace
           WHERE nspname !~ '^pg_' AND nspname <> 'information_schema'
  LOOP
    EXECUTE format('REVOKE USAGE, CREATE ON SCHEMA %I FROM PUBLIC, %s', n.nspname, __ROLES__);
    EXECUTE format('REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA %I FROM PUBLIC, %s', n.nspname, __ROLES__);
  END LOOP;
END
$isolation$;
'@
    $isolation = $isolation.Replace('__ROLES__', $rolesLiteral)
    # Solo operadores en loopback: createdb y el cierre son comandos consecutivos, no atomicos.
    $phase = 'creacion y aislamiento'
    $trialStart = [DateTimeOffset]::UtcNow
    $age = $trialStart - $start
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Pg 'createdb' ($conn + @('--maintenance-db=postgres','--template=template0','foodstore_restore_test')) | Out-Null
    $fence = "ALTER DATABASE foodstore_restore_test CONNECTION LIMIT 0; " +
        "REVOKE CONNECT, TEMPORARY ON DATABASE foodstore_restore_test FROM PUBLIC, $roles;"
    Pg 'psql' ($psql + @('-d','postgres','-c',$fence)) | Out-Null
    $active = "SELECT count(*) FROM pg_stat_activity WHERE datname='foodstore_restore_test';"
    if ((Pg 'psql' ($psql + @('-d','postgres','-c',$active)) | Out-String).Trim() -ne '0') {
        throw 'Hay otras conexiones al destino; no se restaura.'
    }
    $phase = 'pg_restore'
    Pg 'pg_restore' ($conn + @('--no-owner','--no-privileges','--exit-on-error','-d','foodstore_restore_test',$dump)) | Out-Null
    $phase = 'aislamiento final y validacion'
    Pg 'psql' ($dest + @('-c', $isolation)) | Out-Null
    Assert-Isolation $dest $literals
    $actual = (Pg 'psql' ($dest + @('-f', $sql)) | Out-String) | ConvertFrom-Json -AsHashtable
    Assert-Baseline $actual
    foreach ($section in @('counts','fingerprints','invalid')) {
        foreach ($key in $m.baseline[$section].Keys) {
            if ($m.baseline[$section][$key] -cne $actual[$section][$key]) { throw 'Comparacion falsa.' }
        }
    }
    $timer.Stop()
    $rto = $timer.Elapsed.TotalSeconds.ToString('F3',[Globalization.CultureInfo]::InvariantCulture)
    $rpo = $age.TotalSeconds.ToString('F3',[Globalization.CultureInfo]::InvariantCulture)
    Log ("medicion inicioUTC=$($trialStart.ToString('o')) RTO_s=$rto RPO_referencia_s=$rpo " +
        "inicioUTC03=$($trialStart.ToOffset([TimeSpan]::FromHours(-3)).ToString('o'))")
    Log "agregados=$($actual | ConvertTo-Json -Compress -Depth 6)"
    if ($timer.Elapsed.TotalSeconds -gt 120 -or $age.TotalHours -gt 24 -or
        $age.TotalSeconds -lt 0) { throw 'Objetivo RTO/RPO incumplido.' }
    $result = [ordered]@{
        status='SUCCESS'; database='foodstore_restore_test'; file=$m.file
        backupStartUtc=$m.startUtc; trialStartUtc=$trialStart.ToString('o')
        validatedUtc=[DateTimeOffset]::UtcNow.ToString('o'); baseline=$m.baseline; actual=$actual
        rtoSeconds=$timer.Elapsed.TotalSeconds; rpoReferenceSeconds=$age.TotalSeconds
        isolated=$true; roleAclRecovery=$false
    }
    $writer = New-Writer (Join-Path $LogDir "restore_$token.result.json")
    try { $writer.Write(($result | ConvertTo-Json -Depth 8)) } finally { $writer.Dispose() }
    Log "SUCCESS restore_test respaldo=$($m.file) destino_aislado=foodstore_restore_test"
} catch {
    if ($null -ne $timer -and $timer.IsRunning) { $timer.Stop() }
    Log "FAILED restore_test fase=$phase"
    exit 1
} finally {
    if ($null -ne $log) { $log.Dispose() }
}
exit 0
