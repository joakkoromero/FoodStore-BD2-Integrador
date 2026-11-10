### backup_foodstore.ps1

```powershell
#requires -Version 7.0
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
$log = $null; $phase = 'preflight'
function Log([string]$Text) {
    $line = "$([DateTimeOffset]::UtcNow.ToString('o')) $Text"
    if ($null -ne $log) { $log.WriteLine($line) }
    [Console]::Error.WriteLine($line)
}
function New-Writer([string]$Path) {
    [IO.StreamWriter]::new([IO.File]::Open($Path, 'CreateNew', 'Write', 'None'), [Text.UTF8Encoding]::new($false))
}
function Assert-Private([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Ruta redirigida.' }
    $allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
    foreach ($ace in (Get-Acl -LiteralPath $Path).Access) {
        if ($ace.AccessControlType -eq 'Allow' -and $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin $allowed) { throw 'ACL no privada.' }
    }
}
function Pg([string]$Name, [string[]]$Arguments) {
    $output = & (Join-Path $PgBin "$Name.exe") @Arguments 2>$null
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$Name: codigo $code" }
    $output
}
function Assert-Baseline($Value) {
    $sets = @{ counts = @('categoria','producto','usuario','pedido','detalle_pedido'); fingerprints = @('categoria','producto','usuario','pedido','detalle_pedido'); invalid = @('productos','detalles','pedidos') }
    if ($Value -isnot [Collections.IDictionary] -or $Value.Count -ne 3) { throw 'JSON base invalido.' }
    foreach ($section in $sets.Keys) {
        $part = $Value[$section]
        if ($part -isnot [Collections.IDictionary] -or $part.Count -ne $sets[$section].Count) { throw 'Claves invalidas.' }
        foreach ($key in $sets[$section]) {
            if (-not $part.Contains($key)) { throw 'Falta clave.' }
            $v = $part[$key]
            if ($section -eq 'fingerprints') {
                if ($v -isnot [string] -or $v -cnotmatch '^[0-9a-f]{64}$') { throw 'Huella invalida.' }
            } elseif (($v -isnot [long] -and $v -isnot [int]) -or $v -lt 0 -or ($section -eq 'invalid' -and $v -ne 0)) { throw 'Conteo o integridad invalidos.' }
        }
    }
}
try {
    if ($HostName -ne '127.0.0.1' -or $Port -ne 55605 -or -not $ConfirmNoWrites) { throw 'Endpoint o ventana sin escrituras no confirmados.' }
    $WorkDir = (Get-Item -LiteralPath $WorkDir).FullName
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { throw 'WorkDir no es directorio.' }
    Assert-Private $WorkDir
    for ($d = Get-Item -LiteralPath $WorkDir; $null -ne $d; $d = $d.Parent) {
        if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) { throw 'WorkDir debe estar fuera de Git y sin redirecciones.' }
    }
    $token = "$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))_$([guid]::NewGuid().ToString('N'))"
    $stem = "foodstore_$token"
    $log = New-Writer (Join-Path $WorkDir "$stem.log"); $log.AutoFlush = $true
    Log 'START backup'
    if (-not $env:PGPASSFILE -or -not (Test-Path -LiteralPath $env:PGPASSFILE -PathType Leaf)) { throw 'Falta PGPASSFILE.' }
    Assert-Private $env:PGPASSFILE
    foreach ($exe in @('psql','pg_dump','pg_restore')) {
        if ((Pg $exe @('--version') | Out-String) -notmatch '\(PostgreSQL\) 17(?:\.|\s|$)') { throw 'Se requieren clientes 17.' }
    }
    $sql = Join-Path $PSScriptRoot 'validaciones.sql'
    if (-not (Test-Path -LiteralPath $sql -PathType Leaf)) { throw 'Falta validaciones.sql.' }
    $conn = @('-h', $HostName, '-p', "$Port", '-U', $DbUser, '-w')
    $psql = @('-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1') + $conn + @('-d', 'foodstore')
    $check = "SELECT (current_setting('server_version_num')::int BETWEEN 170000 AND 179999 AND (SELECT rolsuper FROM pg_roles WHERE rolname=current_user))::int;"
    if ((Pg 'psql' ($psql + @('-c', $check)) | Out-String).Trim() -ne '1') { throw 'Se requiere servidor 17 y administrador bootstrap.' }
    $started = [DateTimeOffset]::UtcNow
    $phase = 'baseline anterior'
    $baseline = (Pg 'psql' ($psql + @('-f', $sql)) | Out-String) | ConvertFrom-Json -AsHashtable
    Assert-Baseline $baseline
    $partial = Join-Path $WorkDir "$stem.partial"; $dump = Join-Path $WorkDir "$stem.dump"
    if ((Test-Path -LiteralPath $partial) -or (Test-Path -LiteralPath $dump)) { throw 'Colision de nombres.' }
    $phase = 'pg_dump'
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
    $manifest = [ordered]@{ status='SUCCESS'; database='foodstore'; startUtc=$started.ToString('o'); endUtc=$ended.ToString('o'); startUtcMinus03=$started.ToOffset([TimeSpan]::FromHours(-3)).ToString('o'); endUtcMinus03=$ended.ToOffset([TimeSpan]::FromHours(-3)).ToString('o'); file="$stem.dump"; size=$size; sha256=$hash; baseline=$baseline }
    $manifestPartial = Join-Path $WorkDir "$stem.manifest.partial"
    $writer = New-Writer $manifestPartial
    try { $writer.Write(($manifest | ConvertTo-Json -Depth 8)) } finally { $writer.Dispose() }
    [IO.File]::Move($manifestPartial, (Join-Path $WorkDir "$stem.manifest.json"))
    Log "SUCCESS backup archivo=$stem.dump bytes=$size sha256=$hash"
} catch {
    Log "FAILED backup fase=$phase"
    exit 1
} finally {
    if ($null -ne $log) { $log.Dispose() }
}
exit 0
```

### health_check.sql

```sql
\set ON_ERROR_STOP on
\pset pager off

SET TIME ZONE 'UTC';

SELECT
    '01_base_y_transacciones' AS seccion,
    clock_timestamp() AS observado_utc,
    datname,
    pg_database_size(datname) AS bytes,
    pg_size_pretty(pg_database_size(datname)) AS tamano,
    numbackends,
    xact_commit,
    xact_rollback,
    deadlocks,
    stats_reset
FROM pg_stat_database
WHERE datname = current_database();

-- Estas cifras de filas son estimaciones, no COUNT exactos.
SELECT
    '02_tablas_estimaciones' AS seccion,
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    n_mod_since_analyze,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    pg_total_relation_size(relid) AS bytes_totales
FROM pg_stat_user_tables
ORDER BY schemaname, relname;

-- No se consulta ni se imprime la columna query.
SELECT
    '03_actividad_actual' AS seccion,
    pid,
    usename,
    application_name,
    state,
    wait_event_type,
    wait_event,
    clock_timestamp() - backend_start AS antiguedad_conexion,
    clock_timestamp() - xact_start AS antiguedad_transaccion,
    clock_timestamp() - query_start AS antiguedad_consulta,
    query_id
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND state = 'active'
ORDER BY query_start, pid;
```

### maintenance.sql

```sql
\set ON_ERROR_STOP on
\pset pager off

SET TIME ZONE 'UTC';

SELECT
    '01_configuracion_observada' AS seccion,
    name,
    setting,
    unit,
    source
FROM pg_settings
WHERE name IN (
    'autovacuum',
    'track_counts',
    'autovacuum_naptime',
    'autovacuum_vacuum_threshold',
    'autovacuum_vacuum_scale_factor',
    'autovacuum_vacuum_insert_threshold',
    'autovacuum_vacuum_insert_scale_factor',
    'autovacuum_analyze_threshold',
    'autovacuum_analyze_scale_factor'
)
ORDER BY name;

SELECT
    '02_estado_previo_estimado' AS seccion,
    s.schemaname,
    s.relname,
    c.reloptions AS opciones_particulares,
    s.n_live_tup,
    s.n_dead_tup,
    s.n_mod_since_analyze,
    s.last_vacuum,
    s.last_autovacuum,
    s.last_analyze,
    s.last_autoanalyze
FROM pg_stat_user_tables AS s
JOIN pg_class AS c ON c.oid = s.relid
ORDER BY s.schemaname, s.relname;

SELECT
    '03_regla_de_decision' AS seccion,
    'Solo ANALYZE puntual: track_counts activo, modificaciones > 0 y '
    'n_mod_since_analyze >= threshold + scale_factor * n_live_tup. '
    'Se respetan overrides de cada tabla. Son estimaciones estadisticas; '
    'los conteos exactos corresponden a validaciones.sql. '
    'Si ninguna tabla cumple, no se ejecuta ANALYZE.' AS criterio;

-- Se observa primero y se actua solo ante el umbral documentado.
-- No se modifica autovacuum ni se programa una compactacion periodica.
WITH observacion AS (
    SELECT
        s.schemaname,
        s.relname,
        s.n_live_tup,
        s.n_mod_since_analyze,
        COALESCE(
            (
                SELECT option_value::numeric
                FROM pg_options_to_table(c.reloptions)
                WHERE option_name = 'autovacuum_analyze_threshold'
            ),
            current_setting('autovacuum_analyze_threshold')::numeric
        ) AS umbral,
        COALESCE(
            (
                SELECT option_value::numeric
                FROM pg_options_to_table(c.reloptions)
                WHERE option_name = 'autovacuum_analyze_scale_factor'
            ),
            current_setting('autovacuum_analyze_scale_factor')::numeric
        ) AS factor
    FROM pg_stat_user_tables AS s
    JOIN pg_class AS c ON c.oid = s.relid
    WHERE c.relkind IN ('r', 'm')
)
SELECT format(
    'SELECT %L AS justificacion; ANALYZE %I.%I;',
    format(
        'ANALYZE puntual de %I.%I: modificaciones estimadas=%s; '
        'umbral efectivo=%s; filas vivas estimadas=%s.',
        schemaname,
        relname,
        n_mod_since_analyze,
        umbral + factor * n_live_tup,
        n_live_tup
    ),
    schemaname,
    relname
)
FROM observacion
WHERE current_setting('track_counts')::boolean
  AND n_mod_since_analyze > 0
  AND n_mod_since_analyze >= umbral + factor * n_live_tup
ORDER BY schemaname, relname
\gexec

SELECT
    '04_fin_mantenimiento' AS seccion,
    clock_timestamp() AS finalizado_utc,
    'Los contadores pueden reflejarse con demora; no equivalen a COUNT.' AS nota;
```

### restore_test.ps1

```powershell
#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$HostName = '127.0.0.1',
    [int]$Port = 55605,
    [Parameter(Mandatory)][string]$DbUser,
    [Parameter(Mandatory)][string]$PgBin,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string[]]$BusinessRoles
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$env:PGCONNECT_TIMEOUT = '10'
$log = $null; $timer = $null; $phase = 'preflight'
function Log([string]$Text) {
    $line = "$([DateTimeOffset]::UtcNow.ToString('o')) $Text"
    if ($null -ne $log) { $log.WriteLine($line) }
    [Console]::Error.WriteLine($line)
}
function New-Writer([string]$Path) {
    [IO.StreamWriter]::new([IO.File]::Open($Path, 'CreateNew', 'Write', 'None'), [Text.UTF8Encoding]::new($false))
}
function Assert-Private([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Ruta redirigida.' }
    $allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
    foreach ($ace in (Get-Acl -LiteralPath $Path).Access) {
        if ($ace.AccessControlType -eq 'Allow' -and $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin $allowed) { throw 'ACL no privada.' }
    }
}
function Pg([string]$Name, [string[]]$Arguments) {
    $output = & (Join-Path $PgBin "$Name.exe") @Arguments 2>$null
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$Name: codigo $code" }
    $output
}
function Assert-Baseline($Value) {
    $sets = @{ counts = @('categoria','producto','usuario','pedido','detalle_pedido'); fingerprints = @('categoria','producto','usuario','pedido','detalle_pedido'); invalid = @('productos','detalles','pedidos') }
    if ($Value -isnot [Collections.IDictionary] -or $Value.Count -ne 3) { throw 'JSON base invalido.' }
    foreach ($section in $sets.Keys) {
        $part = $Value[$section]
        if ($part -isnot [Collections.IDictionary] -or $part.Count -ne $sets[$section].Count) { throw 'Claves invalidas.' }
        foreach ($key in $sets[$section]) {
            if (-not $part.Contains($key)) { throw 'Falta clave.' }
            $v = $part[$key]
            if ($section -eq 'fingerprints') {
                if ($v -isnot [string] -or $v -cnotmatch '^[0-9a-f]{64}$') { throw 'Huella invalida.' }
            } elseif (($v -isnot [long] -and $v -isnot [int]) -or $v -lt 0 -or ($section -eq 'invalid' -and $v -ne 0)) { throw 'Conteo o integridad invalidos.' }
        }
    }
}
try {
    if ($HostName -ne '127.0.0.1' -or $Port -ne 55605) { throw 'Endpoint no permitido.' }
    $WorkDir = (Get-Item -LiteralPath $WorkDir).FullName
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { throw 'WorkDir no es directorio.' }
    Assert-Private $WorkDir
    for ($d = Get-Item -LiteralPath $WorkDir; $null -ne $d; $d = $d.Parent) {
        if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) { throw 'WorkDir debe estar fuera de Git y sin redirecciones.' }
    }
    $token = "$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))_$([guid]::NewGuid().ToString('N'))"
    $log = New-Writer (Join-Path $WorkDir "restore_$token.log"); $log.AutoFlush = $true
    Log 'START restore_test'
    if (-not $env:PGPASSFILE -or -not (Test-Path -LiteralPath $env:PGPASSFILE -PathType Leaf)) { throw 'Falta PGPASSFILE.' }
    Assert-Private $env:PGPASSFILE
    foreach ($exe in @('psql','createdb','pg_restore')) {
        if ((Pg $exe @('--version') | Out-String) -notmatch '\(PostgreSQL\) 17(?:\.|\s|$)') { throw 'Se requieren clientes 17.' }
    }
    if ($BusinessRoles.Count -ne 6 -or @($BusinessRoles | Sort-Object -Unique -CaseSensitive).Count -ne 6 -or @($BusinessRoles | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count) { throw 'Indicar seis roles distintos.' }
    $roles = ($BusinessRoles | ForEach-Object { '"' + $_.Replace('"','""') + '"' }) -join ', '
    $literals = ($BusinessRoles | ForEach-Object { "'" + $_.Replace("'","''") + "'" }) -join ', '
    $rolesLiteral = "'" + $roles.Replace("'","''") + "'"
    $conn = @('-h', $HostName, '-p', "$Port", '-U', $DbUser, '-w')
    $psql = @('-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1') + $conn
    $checkSql = "SELECT json_build_object('version',current_setting('server_version_num')::int,'admin',(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),'exists',EXISTS(SELECT FROM pg_database WHERE datname='foodstore_restore_test'),'roles',(SELECT count(*) FROM pg_roles WHERE rolname IN ($literals) AND NOT rolsuper AND rolname<>current_user));"
    $check = (Pg 'psql' ($psql + @('-d','postgres','-c',$checkSql)) | Out-String) | ConvertFrom-Json -AsHashtable
    if ($check.version -lt 170000 -or $check.version -ge 180000 -or $check.admin -ne $true -or $check.exists -ne $false -or $check.roles -ne 6) { throw 'Servidor, administrador, destino o roles no validos.' }
    $sql = Join-Path $PSScriptRoot 'validaciones.sql'
    if (-not (Test-Path -LiteralPath $sql -PathType Leaf)) { throw 'Falta validaciones.sql.' }
    $candidates = @(foreach ($file in Get-ChildItem -LiteralPath $WorkDir -Filter '*.manifest.json' -File) {
        Assert-Private $file.FullName
        $m = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        if ($m.status -ceq 'SUCCESS') {
            $end = [DateTimeOffset]::ParseExact($m.endUtc, 'o', [Globalization.CultureInfo]::InvariantCulture)
            [pscustomobject]@{ Manifest=$m; End=$end }
        }
    })
    if ($candidates.Count -eq 0) { throw 'No hay manifiesto exitoso.' }
    $chosen = $candidates | Sort-Object End -Descending | Select-Object -First 1
    $m = $chosen.Manifest
    $start = [DateTimeOffset]::ParseExact($m.startUtc, 'o', [Globalization.CultureInfo]::InvariantCulture)
    if ($m.database -cne 'foodstore' -or $start.Offset -ne [TimeSpan]::Zero -or $chosen.End.Offset -ne [TimeSpan]::Zero -or $chosen.End -lt $start -or $chosen.End -gt [DateTimeOffset]::UtcNow) { throw 'Metadatos temporales invalidos.' }
    if ($m.file -isnot [string] -or $m.file -cnotmatch '^foodstore_[0-9]{8}T[0-9]{13}Z_[0-9a-f]{32}\.dump$') { throw 'Nombre de archivo no permitido.' }
    if (($m.size -isnot [long] -and $m.size -isnot [int]) -or $m.size -le 0 -or $m.sha256 -isnot [string] -or $m.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Tamano o hash invalido.' }
    Assert-Baseline $m.baseline
    $dump = Join-Path $WorkDir $m.file
    if (-not (Test-Path -LiteralPath $dump -PathType Leaf)) { throw 'Falta respaldo.' }
    Assert-Private $dump
    if ((Get-Item -LiteralPath $dump).Length -ne $m.size -or (Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash.ToLowerInvariant() -cne $m.sha256) { throw 'Respaldo alterado.' }
    Pg 'pg_restore' @('--list', $dump) | Out-Null
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
    $phase = 'creacion y aislamiento'
    $trialStart = [DateTimeOffset]::UtcNow
    $age = $trialStart - $start
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Pg 'createdb' ($conn + @('--maintenance-db=postgres','--template=template0','--connection-limit=0','foodstore_restore_test')) | Out-Null
    Pg 'psql' ($dest + @('-c', "REVOKE CONNECT, TEMPORARY ON DATABASE foodstore_restore_test FROM PUBLIC, $roles;")) | Out-Null
    $phase = 'pg_restore'
    Pg 'pg_restore' ($conn + @('--no-owner','--no-privileges','--exit-on-error','-d','foodstore_restore_test',$dump)) | Out-Null
    $phase = 'aislamiento final y validacion'
    Pg 'psql' ($dest + @('-c', $isolation)) | Out-Null
    $actual = (Pg 'psql' ($dest + @('-f', $sql)) | Out-String) | ConvertFrom-Json -AsHashtable
    Assert-Baseline $actual
    foreach ($section in @('counts','fingerprints','invalid')) {
        foreach ($key in $m.baseline[$section].Keys) {
            if ($m.baseline[$section][$key] -cne $actual[$section][$key]) { throw 'Comparacion falsa.' }
        }
    }
    $timer.Stop()
    Log "medicion inicioUTC=$($trialStart.ToString('o')) inicioUTC03=$($trialStart.ToOffset([TimeSpan]::FromHours(-3)).ToString('o')) RTO_s=$($timer.Elapsed.TotalSeconds.ToString('F3',[Globalization.CultureInfo]::InvariantCulture)) RPO_referencia_s=$($age.TotalSeconds.ToString('F3',[Globalization.CultureInfo]::InvariantCulture))"
    Log "agregados=$($actual | ConvertTo-Json -Compress -Depth 6)"
    if ($timer.Elapsed.TotalSeconds -gt 120 -or $age.TotalHours -gt 24 -or $age.TotalSeconds -lt 0) { throw 'Objetivo RTO/RPO incumplido.' }
    Log "SUCCESS restore_test respaldo=$($m.file) destino_aislado=foodstore_restore_test"
} catch {
    if ($null -ne $timer -and $timer.IsRunning) { $timer.Stop() }
    Log "FAILED restore_test fase=$phase"
    exit 1
} finally {
    if ($null -ne $log) { $log.Dispose() }
}
exit 0
```

### validaciones.sql

```sql
\set ON_ERROR_STOP on

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

SET LOCAL TIME ZONE 'UTC';
SET LOCAL DateStyle = 'ISO, YMD';
SET LOCAL IntervalStyle = 'postgres';
SET LOCAL bytea_output = 'hex';
SET LOCAL extra_float_digits = 3;

-- Cada huella incluye todas las columnas y todas las filas,
-- incluidas las dadas de baja logicamente. No se exportan filas.
-- JSONB estabiliza el orden de las claves; ORDER BY estabiliza las filas.
WITH
categoria AS (
    SELECT
        count(*) AS n,
        encode(
            sha256(convert_to(
                COALESCE(
                    string_agg(to_jsonb(t)::text, E'\n' ORDER BY t.id),
                    ''
                ),
                'UTF8'
            )),
            'hex'
        ) AS fingerprint
    FROM public.categoria AS t
),
producto AS (
    SELECT
        count(*) AS n,
        encode(
            sha256(convert_to(
                COALESCE(
                    string_agg(to_jsonb(t)::text, E'\n' ORDER BY t.id),
                    ''
                ),
                'UTF8'
            )),
            'hex'
        ) AS fingerprint
    FROM public.producto AS t
),
usuario AS (
    SELECT
        count(*) AS n,
        encode(
            sha256(convert_to(
                COALESCE(
                    string_agg(to_jsonb(t)::text, E'\n' ORDER BY t.id),
                    ''
                ),
                'UTF8'
            )),
            'hex'
        ) AS fingerprint
    FROM public.usuario AS t
),
pedido AS (
    SELECT
        count(*) AS n,
        encode(
            sha256(convert_to(
                COALESCE(
                    string_agg(to_jsonb(t)::text, E'\n' ORDER BY t.id),
                    ''
                ),
                'UTF8'
            )),
            'hex'
        ) AS fingerprint
    FROM public.pedido AS t
),
detalle_pedido AS (
    SELECT
        count(*) AS n,
        encode(
            sha256(convert_to(
                COALESCE(
                    string_agg(
                        to_jsonb(t)::text,
                        E'\n' ORDER BY t.pedido_id, t.producto_id
                    ),
                    ''
                ),
                'UTF8'
            )),
            'hex'
        ) AS fingerprint
    FROM public.detalle_pedido AS t
),
productos_invalidos AS (
    SELECT count(*) AS n
    FROM public.producto AS p
    WHERE p.precio IS NULL
       OR p.precio < 0
       OR p.stock IS NULL
       OR p.stock < 0
       OR NOT EXISTS (
           SELECT 1
           FROM public.categoria AS c
           WHERE c.id = p.categoria_id
       )
),
detalles_invalidos AS (
    SELECT count(*) AS n
    FROM public.detalle_pedido AS d
    WHERE d.cantidad IS NULL
       OR d.cantidad <= 0
       OR d.precio_unitario IS NULL
       OR d.precio_unitario < 0
       OR d.subtotal IS DISTINCT FROM d.cantidad * d.precio_unitario
       OR NOT EXISTS (
           SELECT 1
           FROM public.pedido AS p
           WHERE p.id = d.pedido_id
       )
       OR NOT EXISTS (
           SELECT 1
           FROM public.producto AS p
           WHERE p.id = d.producto_id
       )
),
totales AS (
    SELECT pedido_id, sum(subtotal) AS total
    FROM public.detalle_pedido
    GROUP BY pedido_id
),
pedidos_invalidos AS (
    SELECT count(*) AS n
    FROM public.pedido AS p
    LEFT JOIN totales AS t ON t.pedido_id = p.id
    WHERE p.total IS DISTINCT FROM COALESCE(t.total, 0)
       OR NOT EXISTS (
           SELECT 1
           FROM public.usuario AS u
           WHERE u.id = p.usuario_id
       )
)
SELECT json_build_object(
    'counts', json_build_object(
        'categoria', c.n,
        'producto', p.n,
        'usuario', u.n,
        'pedido', pe.n,
        'detalle_pedido', d.n
    ),
    'fingerprints', json_build_object(
        'categoria', c.fingerprint,
        'producto', p.fingerprint,
        'usuario', u.fingerprint,
        'pedido', pe.fingerprint,
        'detalle_pedido', d.fingerprint
    ),
    'invalid', json_build_object(
        'productos', pi.n,
        'detalles', di.n,
        'pedidos', pei.n
    )
) AS validacion
FROM categoria AS c
CROSS JOIN producto AS p
CROSS JOIN usuario AS u
CROSS JOIN pedido AS pe
CROSS JOIN detalle_pedido AS d
CROSS JOIN productos_invalidos AS pi
CROSS JOIN detalles_invalidos AS di
CROSS JOIN pedidos_invalidos AS pei;

COMMIT;
```

Decisiones y límites:

- **Estos son fuentes propuestos, no ejecutados ni certificados.** No utilicé herramientas, conexiones ni credenciales. La revisión y prueba del operador siguen pendientes.
- `validaciones.sql` debe estar junto a ambos `.ps1`. `WorkDir` debe existir, estar fuera de Git y tener ACL privada. La comprobación acepta permisos de acceso únicamente para el usuario Windows actual, `SYSTEM` y administradores locales. Las operaciones `.NET` usan rutas literales y creación o movimiento sin sobrescritura.
- **Hay una corrección sintáctica necesaria en ambos fuentes PowerShell antes de ejecutarlos:** en `Pg`, la expresión de error debe escribirse `throw "${Name}: codigo $code"` en lugar de `throw "$Name: codigo $code"`. PowerShell interpreta el colon inmediatamente posterior al nombre como parte de una referencia de variable.
- `-ConfirmNoWrites` confirma una **ventana sin escrituras establecida externamente**. No bloquea escritores. Las dos líneas base detectan diferencias observables, pero no modificaciones revertidas entre mediciones ni cambios de DDL. Cada validación tiene su propio snapshot; ninguno se presenta como compartido con `pg_dump`.
- `BusinessRoles` exige los **seis nombres reales de U5**, no suministrados en los adjuntos. Se verifica que existan, no sean superusuarios y no sean el restaurador. El límite de conexiones cero impide conexiones normales desde la creación, pero permite superusuarios. No constituye aislamiento frente a otros administradores.
- El respaldo completo incluye esquemas, funciones, índices, vistas y materializadas; las comparaciones ejecutables cubren las cinco tablas solicitadas. **No certifican equivalencia de definiciones, contenido de otras tablas ni políticas de seguridad.** Las funciones `SECURITY DEFINER` quedan bajo el propietario de restauración; el destino permanece cerrado a la aplicación.
- Las huellas SHA-256 usan una agregación completa por tabla. Consumen memoria y están sujetas al límite de tamaño de los valores PostgreSQL. Debe comprobarse su viabilidad con el volumen real; no son una estrategia de hashing para tablas arbitrariamente grandes.
- Se conservan parciales y destinos fallidos para inspección. Un `.dump` sin manifiesto publicado no es elegible. No hay borrado, reintento destructivo ni selección silenciosa de un respaldo anterior cuando falla la integridad del elegido.
- El ensayo considera incumplidos los objetivos si el RTO supera 120 segundos o la antigüedad conservadora supera 24 horas. Esa antigüedad se calcula desde el inicio registrado del respaldo, no desde su cierre, y **no mide pérdida real ni proporciona PITR**.
- Los fallos anteriores a poder abrir un log privado registran `FAILED` en stderr. Los errores nativos se reducen a fase y código para no incorporar mensajes potencialmente sensibles al registro entregable. No se programan tareas ni se genera aquí el PDF.
