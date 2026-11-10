# Fuentes saneadas para revisión estática: Unidad6

No ejecutar estas copias. Los literales personales/de carga se sustituyeron por placeholders; las comprobaciones en motor usarán las fuentes originales locales. Señalar archivo/línea y distinguir errores confirmables de hipótesis.

## outputs\Arancibia_Romero_U6\food-store-tp-u6\backup_foodstore.ps1

SHA256 original: 53612efb8f616d8cf1ff763d998d1155dce13d40b6aa1784e634d299404aa9f5
SHA256 saneado: 952c9698eec5c238b366ed137c646f018f6d5a7ec332e7f60e97cc6ba0619d3f

`````ps1
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
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

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\health_check.sql

SHA256 original: 948cbbb741032238ac6609e65338a6890bf25c0b41fd079a345943ed5f68fede
SHA256 saneado: c38aa625944aa7a6537b3607fd728888e6d890ef9cb2fd3a6314ddba802648a8

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Unidad 6 - Food Store. Exequiel Arancibia / Joaquin Romero.
-- Implementacion tecnica: Codex, segun SPEC_U6.md y AGENTS.md.
-- Uso: psql -X -w -v ON_ERROR_STOP=1 -d foodstore -f health_check.sql
-- Solo agregados/estadisticas. No exporta filas ni texto SQL de sesiones.
\set ON_ERROR_STOP on
\set QUIET 1
\pset pager off
\pset null '(NULL)'

BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL TIME ZONE 'America/Argentina/Buenos_Aires';
SET LOCAL application_name = 'u6_health_check';

DO $base_correcta$
BEGIN
    IF pg_catalog.current_database() <> 'foodstore' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'health_check.sql requiere la base foodstore';
    END IF;
END
$base_correcta$;

\echo 'CONTROL 1 - Tamano de la base principal'
SELECT pg_catalog.current_database() AS base,
       pg_catalog.clock_timestamp() AS observado_en,
       pg_catalog.pg_database_size(pg_catalog.current_database()) AS bytes,
       pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(pg_catalog.current_database())) AS tamano;

\echo 'CONTROL 2 - Conexiones y contadores acumulados; no son tasas ni filas de negocio'
SELECT datname AS base, numbackends AS conexiones,
       xact_commit AS transacciones_confirmadas,
       xact_rollback AS transacciones_revertidas,
       deadlocks AS interbloqueos, stats_reset AS reinicio_contadores
FROM pg_catalog.pg_stat_database
WHERE datname = pg_catalog.current_database();

\echo 'CONTROL 3 - Estado estimado de tablas; n_live_tup NO equivale a COUNT(*)'
SELECT schemaname AS esquema, relname AS tabla,
       n_live_tup AS filas_vivas_estimadas,
       n_dead_tup AS tuplas_muertas_estimadas,
       n_mod_since_analyze AS cambios_estimados_desde_analyze,
       last_vacuum, last_autovacuum, last_analyze, last_autoanalyze
FROM pg_catalog.pg_stat_user_tables
ORDER BY n_dead_tup DESC, schemaname, relname;

\echo 'CONTROL 4 - Consultas activas ajenas al chequeo; sin texto SQL, usuario ni direccion'
-- pg_stat_activity.query solo se usa para una clasificacion de lista cerrada.
-- WITH puede contener escrituras: no se rotula automaticamente como lectura.
-- Los application_name no reconocidos tambien se ocultan porque son texto libre.
SELECT pid, backend_type AS tipo_backend, state AS estado,
       pg_catalog.clock_timestamp() - query_start AS duracion,
       wait_event_type AS tipo_espera, wait_event AS espera,
       CASE
           WHEN application_name IN ('psql','pg_dump','pg_restore','u6_backup','u6_restore_test')
               THEN application_name
           ELSE '[aplicacion omitida]'
       END AS aplicacion,
       CASE
           WHEN query ~* '^[[:space:]]*SELECT([[:space:](]|$)' THEN 'SELECT'
           WHEN query ~* '^[[:space:]]*WITH([[:space:](]|$)' THEN 'WITH'
           WHEN query ~* '^[[:space:]]*INSERT([[:space:]]|$)' THEN 'INSERT'
           WHEN query ~* '^[[:space:]]*UPDATE([[:space:]]|$)' THEN 'UPDATE'
           WHEN query ~* '^[[:space:]]*DELETE([[:space:]]|$)' THEN 'DELETE'
           WHEN query ~* '^[[:space:]]*ANALYZE([[:space:](]|$)' THEN 'ANALYZE'
           WHEN query ~* '^[[:space:]]*VACUUM([[:space:](]|$)' THEN 'VACUUM'
           ELSE 'OTRA / NO VISIBLE'
       END AS clase_de_consulta
FROM pg_catalog.pg_stat_activity
WHERE datname = pg_catalog.current_database()
  AND state = 'active'
  AND pid <> pg_catalog.pg_backend_pid()
ORDER BY query_start NULLS LAST, pid;

COMMIT;

-- Cero consultas activas es un resultado valido; no se fabrica actividad.
-- Usuarios sin pg_read_all_stats pueden tener visibilidad limitada de otras
-- sesiones. Las estadisticas pueden retrasarse; NULL no prueba daemon apagado.

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\maintenance.sql

SHA256 original: 18f3becf82ebf07db6899692dbe7eb1c57838cf1528699a75ca7c0627bf0840b
SHA256 saneado: fac7bd5e65ab68d5118adda8230700619126cd019a08ebcb71a406d1b032b1c1

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Unidad 6 - Food Store. Exequiel Arancibia / Joaquin Romero.
-- Implementacion tecnica: Codex, segun SPEC_U6.md y observacion previa.
-- Uso: psql -X -w -v ON_ERROR_STOP=1 -d foodstore -f maintenance.sql
-- No modifica filas, permisos ni autovacuum. Actualiza estadisticas puntuales.
-- Ejecutar como operador tecnico autorizado, no como login de aplicacion.
\set ON_ERROR_STOP on
\set QUIET 1
\pset pager off
\pset null '(NULL)'

SET search_path = pg_catalog;
SET TIME ZONE 'America/Argentina/Buenos_Aires';
SET application_name = 'u6_maintenance';
SET lock_timeout = '5s';
SET statement_timeout = '60s';

DO $base_correcta$
BEGIN
    IF pg_catalog.current_database() <> 'foodstore' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'maintenance.sql requiere la base foodstore';
    END IF;
END
$base_correcta$;

\echo 'ANTES 1 - Configuracion efectiva de autovacuum y recoleccion de estadisticas'
SELECT pg_catalog.clock_timestamp() AS observado_en,
       pg_catalog.current_setting('autovacuum') AS autovacuum,
       pg_catalog.current_setting('track_counts') AS track_counts,
       pg_catalog.current_setting('autovacuum_analyze_threshold') AS umbral_analyze,
       pg_catalog.current_setting('autovacuum_analyze_scale_factor') AS factor_analyze,
       pg_catalog.current_setting('autovacuum_vacuum_threshold') AS umbral_vacuum,
       pg_catalog.current_setting('autovacuum_vacuum_scale_factor') AS factor_vacuum;

\echo 'ANTES 2 - Tablas de la copia: estimaciones e historiales, con opciones por tabla'
SELECT s.schemaname AS esquema, s.relname AS tabla,
       s.n_live_tup AS filas_vivas_estimadas,
       s.n_dead_tup AS tuplas_muertas_estimadas,
       s.n_mod_since_analyze AS cambios_estimados_desde_analyze,
       s.last_vacuum, s.last_autovacuum, s.last_analyze, s.last_autoanalyze,
       c.reloptions AS opciones_de_tabla
FROM pg_catalog.pg_stat_user_tables AS s
JOIN pg_catalog.pg_class AS c ON c.oid = s.relid
ORDER BY s.n_dead_tup DESC, s.schemaname, s.relname;

\echo 'ANTES 3 - Conteos reales de las dos tablas elegidas; no inferir vaciado de una estimacion 0'
SELECT 'pedido' AS tabla, pg_catalog.count(*) AS filas_reales FROM public.pedido
UNION ALL
SELECT 'detalle_pedido', pg_catalog.count(*) FROM public.detalle_pedido;

\echo 'DECISION - ANALYZE puntual si last_analyze y last_autoanalyze son ambos NULL por tabla'
-- Observacion previa de esta copia: autovacuum=on, ambas tablas tienen
-- filas reales y estimaciones/historiales recien iniciados. Ausencia de
-- historial NO demuestra ausencia de pg_statistic. Se admite refrescar una
-- linea base documentada de la copia, sin reclamar tuplas muertas inexistentes.
-- No hay motivo observado para VACUUM FULL ni para desactivar autovacuum.
SELECT relname AS tabla,
       CASE WHEN last_analyze IS NULL AND last_autoanalyze IS NULL
            THEN 'ANALYZE puntual: establecer linea base de la copia'
            ELSE 'Sin ANALYZE manual: ya hay historial registrado'
       END AS decision
FROM pg_catalog.pg_stat_user_tables
WHERE relid IN ('public.pedido'::pg_catalog.regclass,
                'public.detalle_pedido'::pg_catalog.regclass)
ORDER BY relname;

-- Cada sentencia de psql se confirma por separado. ANALYZE es admisible
-- dentro de DO; no se utiliza VACUUM, que tiene otras restricciones.
DO $analyze_condicional$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_stat_user_tables
        WHERE relid = 'public.pedido'::pg_catalog.regclass
          AND last_analyze IS NULL AND last_autoanalyze IS NULL
    ) THEN
        EXECUTE 'ANALYZE public.pedido';
        RAISE NOTICE 'ANALYZE public.pedido completado para la linea base de la copia';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_stat_user_tables
        WHERE relid = 'public.detalle_pedido'::pg_catalog.regclass
          AND last_analyze IS NULL AND last_autoanalyze IS NULL
    ) THEN
        EXECUTE 'ANALYZE public.detalle_pedido';
        RAISE NOTICE 'ANALYZE public.detalle_pedido completado para la linea base de la copia';
    END IF;
END
$analyze_condicional$;

-- Descartar cualquier cache estadistica del lector antes de la observacion
-- posterior; el servidor puede tener un breve retraso de publicacion.
DO $lectura_nueva$
BEGIN
    PERFORM pg_catalog.pg_stat_clear_snapshot();
END
$lectura_nueva$;

\echo 'DESPUES - Valores realmente visibles, sin sustituir NULL por un resultado inventado'
SELECT schemaname AS esquema, relname AS tabla,
       n_live_tup AS filas_vivas_estimadas,
       n_dead_tup AS tuplas_muertas_estimadas,
       n_mod_since_analyze AS cambios_estimados_desde_analyze,
       last_analyze, last_autoanalyze,
       analyze_count AS analyze_manuales_registrados
FROM pg_catalog.pg_stat_user_tables
WHERE relid IN ('public.pedido'::pg_catalog.regclass,
                'public.detalle_pedido'::pg_catalog.regclass)
ORDER BY relname;

-- Si aparece historial al repetir, la condicion evita ANALYZE innecesario.
-- Esta politica es del laboratorio; NULL aislado no prueba estadisticas malas.

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\restore_test.ps1

SHA256 original: ab21a4341508d89aacc5fb5479d81f9042704ffb682d8705905ec58baeb7c8e9
SHA256 saneado: 7105699ae296c2873cc527a22776d267e5bf4d512ca76f603984ae9185810bcd

`````ps1
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
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

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\tools\generar_informe_u6.py

SHA256 original: 79c67256ea9330ac0b37281c297e49cf5749bc672f531bbabcdce5968ecde3f7
SHA256 saneado: 9abf217b94875e652ef973425d5c1bbdf888869352c89ce3c009419e1051bade

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Build the single U6 PDF with complete visible and embedded public sources.

No database commands are executed. Inputs must already contain real results.
--check-layout measures short reports without producing any PDF or QA file.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import tempfile
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Flowable, Frame, PageBreak, PageTemplate, Paragraph,
    Preformatted, Spacer, Table, TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents
from pypdf import PdfReader, PdfWriter

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT.parent / 'output/pdf/informe_u6.pdf'
BLUE = colors.HexColor('#153956')
TEAL = colors.HexColor('#087F8C')
PALE = colors.HexColor('#EDF4F7')
INK = colors.HexColor('#243443')
MARGIN = 42
BOTTOM = 48
TOP = 42
WIDTH = A4[0] - MARGIN * 2
HEIGHT = A4[1] - TOP - BOTTOM
MAX_CODE_CHARACTERS = 105
FORBIDDEN_PARTS = {'.git', 'private', 'privado', 'runtime', 'logs', 'backups',
                   '__pycache__', 'node_modules', 'output', 'consigna_qa'}
SECRET_PATTERNS = (
    r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    r'\b(?:sk-proj-|sk-)[A-Za-z0-9_-]{24,}\b',
    r'\b(?:ghp_|github_pat_)[A-Za-z0-9_]{24,}\b',
    r'(?i)\bpostgres(?:ql)?://[^\s/:<>]+:[^\s/@<>]+@',
    r'(?im)^\s*\$?env:PGPASSWORD\s*=\s*[\'"][^\'"\r\n<>]{4,}[\'"]',
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def register_fonts():
    font_dir = Path('C:/Windows/Fonts')
    for name, filename in [('Arial', 'arial.ttf'), ('ArialBold', 'arialbd.ttf'),
                           ('ArialItalic', 'ariali.ttf'), ('ArialBoldItalic', 'arialbi.ttf'),
                           ('Consolas', 'consola.ttf')]:
        path = font_dir / filename
        if not path.is_file():
            raise FileNotFoundError('Required Windows font is missing: ' + filename)
        if name not in pdfmetrics.getRegisteredFontNames():
            pdfmetrics.registerFont(TTFont(name, str(path)))
    pdfmetrics.registerFontFamily('Arial', normal='Arial', bold='ArialBold',
                                  italic='ArialItalic', boldItalic='ArialBoldItalic')


def make_styles():
    return {
        'h1': ParagraphStyle('U6Heading1', fontName='ArialBold', fontSize=17,
                             leading=20, textColor=BLUE, spaceAfter=10, keepWithNext=True),
        'h2': ParagraphStyle('U6Heading2', fontName='ArialBold', fontSize=11.7,
                             leading=14, textColor=TEAL, spaceBefore=8,
                             spaceAfter=5, keepWithNext=True),
        'body': ParagraphStyle('U6Body', fontName='Arial', fontSize=10,
                               leading=13.2, textColor=INK, spaceAfter=6,
                               splitLongWords=True, allowWidows=0, allowOrphans=0),
        'list': ParagraphStyle('U6List', fontName='Arial', fontSize=10,
                               leading=13.2, textColor=INK, spaceAfter=4,
                               leftIndent=12, firstLineIndent=-12, splitLongWords=True,
                               allowWidows=0, allowOrphans=0),
        'small': ParagraphStyle('U6Small', fontName='Arial', fontSize=8.3,
                                leading=10.3, textColor=INK, spaceAfter=5,
                                splitLongWords=True),
        'cell': ParagraphStyle('U6Cell', fontName='Arial', fontSize=8.5,
                               leading=10.5, textColor=INK, splitLongWords=True),
        'headcell': ParagraphStyle('U6HeadCell', fontName='ArialBold', fontSize=8.5,
                                   leading=10.5, textColor=colors.white, splitLongWords=True),
        'code': ParagraphStyle('U6Code', fontName='Consolas', fontSize=8.1,
                               leading=9.8, textColor=INK, spaceAfter=0),
        'toc': ParagraphStyle('U6Toc', fontName='Arial', fontSize=9.2,
                              leading=12, textColor=INK, spaceBefore=5,
                              spaceAfter=5, leftIndent=0, firstLineIndent=0),
    }


def plain_markup(text):
    text = escape(text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)
    def link(match):
        label, target = match.group(1), match.group(2)
        if target.startswith(('https://', 'http://')):
            return '<link href="' + target.replace('"', '&quot;') + '">' + label + '</link>'
        return label if label == target else label + ' (' + target + ')'
    return re.sub(r'\[([^\]]+)\]\(([^)]+)\)', link, text)


def markup(text):
    """Parse code spans after joining Markdown continuation lines."""
    parts = []; start = 0
    for match in re.finditer(r'(`+)(.*?)\1', text, re.S):
        parts.append(plain_markup(text[start:match.start()]))
        code = match.group(2).replace('\n', ' ')
        parts.append('<font name="Consolas">' + escape(code) + '</font>')
        start = match.end()
    parts.append(plain_markup(text[start:]))
    return ''.join(parts)


def table_cells(line):
    line = line.strip()
    if line.startswith('|'): line = line[1:]
    if line.endswith('|') and not line.endswith('\\|'): line = line[:-1]
    cells = []; current = []; delimiter = 0; i = 0
    while i < len(line):
        if line[i:i+2] == '\\|':
            current.append('|'); i += 2; continue
        if line[i] == '`':
            end = i + 1
            while end < len(line) and line[end] == '`': end += 1
            run = end-i
            if delimiter == 0: delimiter = run
            elif delimiter == run: delimiter = 0
            current.append(line[i:end]); i = end; continue
        if line[i] == '|' and delimiter == 0:
            cells.append(''.join(current).strip()); current = []
        else:
            current.append(line[i])
        i += 1
    cells.append(''.join(current).strip())
    return cells


def starts_block(line):
    value = line.lstrip()
    return (bool(re.match(r'^(?:#{1,6}\s|`{3,}|~{3,}|[-*+]\s|\d+[.)]\s|\|)', value))
            or value in ('---', '***'))


class SectionMarker(Flowable):
    def __init__(self, key, title='', *, limited=False, end=False):
        Flowable.__init__(self)
        self.key = key; self.title = title; self.limited = limited; self.end = end
        self.width = self.height = 0

    def draw(self):
        pass


class U6Document(BaseDocTemplate):
    def __init__(self, filename, **kwargs):
        super().__init__(filename, pagesize=A4, leftMargin=MARGIN, rightMargin=MARGIN,
                         topMargin=TOP, bottomMargin=BOTTOM, **kwargs)
        self.addPageTemplates(PageTemplate(id='U6',
            frames=[Frame(MARGIN, BOTTOM, WIDTH, HEIGHT,
                          leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)],
            onPage=self.decorate_page))

    def beforeDocument(self):
        self.sections = {}; self.active_limit = None; self.topic = 'Mantenimiento de Food Store'

    def decorate_page(self, canvas, doc):
        if self.active_limit and doc.page > self.sections[self.active_limit]['start']:
            raise ValueError('One-page limit exceeded: ' + self.active_limit)
        canvas.saveState()
        canvas.setFillColor(INK); canvas.setFont('Arial', 7.8)
        canvas.drawString(MARGIN, A4[1]-25, 'BASES DE DATOS II | TP UNIDAD 6')
        canvas.setStrokeColor(colors.HexColor('#D3E0E7'))
        canvas.line(MARGIN, 36, A4[0]-MARGIN, 36)
        canvas.drawString(MARGIN, 24, 'Food Store | Exequiel Arancibia / Joaquin Romero')
        canvas.drawRightString(A4[0]-MARGIN, 24, str(doc.page))
        canvas.restoreState()

    def afterFlowable(self, flowable):
        if isinstance(flowable, SectionMarker):
            if flowable.end:
                self.sections[flowable.key]['end'] = self.page
                if self.active_limit == flowable.key: self.active_limit = None
            else:
                self.sections[flowable.key] = {'title': flowable.title, 'start': self.page}
                self.topic = flowable.title
                if flowable.limited: self.active_limit = flowable.key
        heading = getattr(flowable, 'u6_bookmark', None)
        if heading:
            key, label, in_toc = heading
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(label, key, level=0, closed=False)
            if in_toc: self.notify('TOCEntry', (0, label, self.page, key))


@dataclass
class Renderer:
    styles: dict

    def __post_init__(self):
        self.wrapped_lines = []

    def paragraph(self, text, style='body', bookmark=None):
        paragraph = Paragraph(markup(text), self.styles[style])
        if bookmark: paragraph.u6_bookmark = bookmark
        return paragraph

    def code(self, lines, source):
        result = []; style = self.styles['code']
        for number, original in enumerate(lines, 1):
            pending = original.expandtabs(4); first = True; pieces = []
            while pending:
                prefix = '' if first else '  '
                limit = min(len(pending), MAX_CODE_CHARACTERS-len(prefix))
                while limit > 0 and pdfmetrics.stringWidth(prefix+pending[:limit],
                                                           'Consolas', style.fontSize) > WIDTH-2:
                    limit -= 1
                if limit == 0: raise ValueError('A source character cannot fit the code frame')
                pieces.append(prefix+pending[:limit]); pending = pending[limit:]; first = False
            if not pieces: pieces = ['']
            if len(pieces) > 1:
                self.wrapped_lines.append({'source': source, 'line': number, 'visual_lines': len(pieces)})
            for piece in pieces: result.append(Preformatted(piece, style))
        result.append(Spacer(1, 7))
        return result

    def table(self, rows, source):
        if not rows or len({len(row) for row in rows}) != 1:
            raise ValueError('Inconsistent Markdown table: ' + source)
        count = len(rows[0])
        ratios = {2: [0.39, 0.61], 3: [0.23, 0.22, 0.55],
                  4: [0.26, 0.24, 0.24, 0.26], 5: [0.23, 0.16, 0.23, 0.23, 0.15]}
        widths = [WIDTH*x for x in ratios.get(count, [1/count]*count)]
        cells = [[self.paragraph(value, 'headcell' if index == 0 else 'cell')
                  for value in row] for index, row in enumerate(rows)]
        table = Table(cells, colWidths=widths, repeatRows=1, hAlign='LEFT', splitInRow=0)
        vertical_padding = 3 if source == 'Source manifest' else 5
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), BLUE),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, PALE]),
            ('LEFTPADDING', (0, 0), (-1, -1), 6),
            ('RIGHTPADDING', (0, 0), (-1, -1), 6),
            ('TOPPADDING', (0, 0), (-1, -1), vertical_padding),
            ('BOTTOMPADDING', (0, 0), (-1, -1), vertical_padding),
            ('LINEBELOW', (0, 0), (-1, 0), 0.5, TEAL),
        ]))
        return [table, Spacer(1, 7)]

    def markdown(self, path):
        lines = path.read_text(encoding='utf-8-sig').splitlines(); result = []; i = 0
        while i < len(lines):
            line = lines[i].strip()
            if not line: i += 1; continue
            fence = re.match(r'^(`{3,}|~{3,})', line)
            if fence:
                delimiter = fence.group(1); block = []; i += 1
                close = re.compile(r'^'+re.escape(delimiter[0])+'{'+str(len(delimiter))+r',}\s*$')
                while i < len(lines) and not close.fullmatch(lines[i].strip()):
                    block.append(lines[i]); i += 1
                if i == len(lines): raise ValueError('Unclosed code block: ' + path.name)
                result.extend(self.code(block, path.relative_to(ROOT).as_posix())); i += 1; continue
            if line.startswith('|'):
                rows = []
                while i < len(lines) and lines[i].lstrip().startswith('|'):
                    row = table_cells(lines[i]); i += 1
                    if not all(re.fullmatch(r':?-{3,}:?', value) for value in row): rows.append(row)
                result.extend(self.table(rows, path.name)); continue
            if line in ('---', '***'): i += 1; continue
            heading = re.match(r'^(#{1,6})\s+(.+)$', line)
            if heading:
                result.append(self.paragraph(heading.group(2), 'h1' if len(heading.group(1)) == 1 else 'h2'))
                i += 1; continue
            item = re.match(r'^([-*+]\s+|\d+[.)]\s+)(.*)$', line)
            block = [line]; i += 1
            # Includes soft line breaks, indented list continuations and code
            # spans whose closing backticks occur on a subsequent source line.
            while i < len(lines) and lines[i].strip() and not starts_block(lines[i]):
                block.append(lines[i].strip()); i += 1
            result.append(self.paragraph('\n'.join(block), 'list' if item else 'body'))
        return result


def public_path(path, *, attachment_only=False):
    resolved = path.resolve()
    if not resolved.is_relative_to(ROOT.resolve()) or not resolved.is_file() or path.is_symlink():
        raise ValueError('Source must be a regular file inside the project')
    relative = resolved.relative_to(ROOT.resolve())
    allowed_extensions = {'.md', '.ps1', '.psm1', '.psd1', '.sql'}
    if attachment_only: allowed_extensions.update({'.json', '.txt', '.csv', '.tsv'})
    if (any(part.casefold() in FORBIDDEN_PARTS for part in relative.parts)
            or resolved.suffix.casefold() not in allowed_extensions
            or any(word in resolved.name.casefold() for word in ('secret', 'pgpass', '.env'))):
        raise ValueError('Private or unsupported source cannot be attached: ' + relative.as_posix())
    text = resolved.read_bytes().decode('utf-8-sig')
    if any(re.search(pattern, text) for pattern in SECRET_PATTERNS):
        raise ValueError('Potential credential in source; local review required: ' + relative.as_posix())
    return resolved


def locate_source(name):
    candidates = []
    for path in ROOT.rglob(name):
        relative = path.relative_to(ROOT)
        if 'docs' in relative.parts or any(part.casefold() in FORBIDDEN_PARTS for part in relative.parts):
            continue
        candidates.append(public_path(path))
    if len(candidates) != 1:
        raise ValueError('Expected exactly one public source named ' + name)
    return candidates[0]


def sources_for(args):
    required = [public_path(ROOT/'SPEC_U6.md'), public_path(ROOT/'AGENTS.md')]
    for name in ('backup_foodstore.ps1', 'health_check.sql', 'maintenance.sql', 'restore_test.ps1'):
        required.append(locate_source(name))
    required.append(public_path(ROOT/args.validation_source) if args.validation_source
                    else locate_source('validaciones.sql'))
    extra = []
    # Companion scripts/modules are real dependencies and must not disappear
    # from a PDF-only delivery. These directories are public source directories.
    for folder in (ROOT, ROOT/'scripts', ROOT/'sql', ROOT/'tools'):
        if folder.is_dir():
            for path in sorted(folder.iterdir()):
                if path.is_file() and path.suffix.casefold() in {'.ps1', '.psm1', '.psd1', '.sql'}:
                    extra.append(public_path(path))
    extra.extend(public_path(ROOT/path) for path in args.source)
    return list(dict.fromkeys(required+extra))


def measure_one_page(flowables):
    # Conservative dry layout: sum even spaces that ReportLab may collapse.
    # The real document also enforces the limit on every build pass.
    used = 0.0
    for flowable in flowables:
        _, height = flowable.wrap(WIDTH, HEIGHT)
        used += height + flowable.getSpaceBefore() + flowable.getSpaceAfter()
    return {'measured_height_points': round(used, 2), 'available_height_points': round(HEIGHT, 2),
            'fits_conservative_measure': used <= HEIGHT}


def add_section(story, renderer, key, title, path, *, limited=False):
    if story: story.append(PageBreak())
    story.append(SectionMarker(key, title, limited=limited))
    story.extend(renderer.markdown(path))
    story.append(SectionMarker(key, end=True))


def verify_embedded(pdf, source_bytes):
    reader = PdfReader(pdf)
    if reader.is_encrypted: raise ValueError('Deliverable unexpectedly encrypted')
    actual = {name: list(values) for name, values in reader.attachments.items()}
    if set(actual) != set(source_bytes): raise ValueError('Embedded source names differ from manifest')
    checks = []
    for name, expected in source_bytes.items():
        if len(actual[name]) != 1 or actual[name][0] != expected:
            raise ValueError('Embedded source bytes differ: ' + name)
        checks.append({'name': name, 'bytes': len(expected), 'sha256': sha256(expected),
                       'extracted_bytes_equal_source': True})
    if any(not page.extract_text().strip() for page in reader.pages):
        raise ValueError('PDF contains an empty text page')
    return reader, checks


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--validation-source', help='Project-relative validation SQL path')
    parser.add_argument('--source', action='append', default=[], help='Additional public source to include')
    parser.add_argument('--attachment-only', action='append', default=[],
                        help='Project-relative public evidence/IA file to embed without a visible code listing; repeatable')
    parser.add_argument('--check-layout', action='store_true', help='Measure existing short reports only')
    args = parser.parse_args(argv)
    register_fonts(); styles = make_styles(); renderer = Renderer(styles)
    short_reports = [('SPEC_U6', ROOT/'SPEC_U6.md'),
                     ('informe_post_incidente', ROOT/'docs/informe_post_incidente.md')]
    measurements = {}
    for key, path in short_reports:
        if not path.is_file():
            if args.check_layout: continue
            raise FileNotFoundError('Required report missing: ' + path.relative_to(ROOT).as_posix())
        measurements[key] = measure_one_page(renderer.markdown(path))
    if args.check_layout:
        print(json.dumps({'pdf_created': False, 'measurements': measurements}, ensure_ascii=False, indent=2))
        return
    renderer.wrapped_lines.clear()
    resolution = ROOT/'docs/resolucion.md'
    if not resolution.is_file(): raise FileNotFoundError('Required report missing: docs/resolucion.md')
    sources = sources_for(args)
    source_bytes = {path.relative_to(ROOT).as_posix(): path.read_bytes() for path in sources}
    attachment_bytes = dict(source_bytes)
    for name in args.attachment_only:
        path = public_path(ROOT/name, attachment_only=True)
        attachment_bytes[path.relative_to(ROOT).as_posix()] = path.read_bytes()
    target = args.output.resolve(); target.parent.mkdir(parents=True, exist_ok=True)
    story = []
    add_section(story, renderer, 'SPEC_U6', 'Especificación U6', ROOT/'SPEC_U6.md', limited=True)
    add_section(story, renderer, 'informe_post_incidente', 'Informe post-incidente',
                ROOT/'docs/informe_post_incidente.md', limited=True)
    add_section(story, renderer, 'resolucion', 'Resolución y evidencias', resolution)
    story.append(PageBreak())
    story.append(renderer.paragraph('Anexos - Índice de fuentes', 'h1',
                                    ('anexos', 'Anexos - Índice de fuentes', False)))
    story.append(renderer.paragraph('Los listados siguientes contienen las fuentes públicas completas. '
        'SPEC_U6.md ya está representada íntegramente en la primera página y no se duplica como listado. '
        'Todos los archivos, incluida SPEC, también se adjuntan individualmente dentro del PDF con sus bytes originales. '
        'Las evidencias y conversaciones de IA adicionales se adjuntan sin repetirlas como listados de código; '
        'el cuerpo contiene su explicación y los resultados pertinentes. '
        'Los ajustes visuales de líneas del listado no modifican esos archivos.', 'body'))
    toc = TableOfContents(); toc.levelStyles = [styles['toc']]; story.append(toc)
    story.append(Spacer(1, 12))
    story.append(renderer.paragraph('Integridad de los adjuntos', 'h2'))
    rows = [['Archivo público', 'SHA-256 de los bytes originales']]
    rows.extend([[name, '`'+sha256(data)+'`'] for name, data in attachment_bytes.items()])
    story.extend(renderer.table(rows, 'Source manifest'))
    for index, path in enumerate(sources[1:], 1):
        relative = path.relative_to(ROOT).as_posix()
        key = 'source-'+str(index); title = f'Anexo {index} - {relative}'
        story.append(PageBreak()); story.append(SectionMarker(key, title))
        story.append(renderer.paragraph(title, 'h1', (key, title, True)))
        story.append(renderer.paragraph('Fuente íntegra | UTF-8 | SHA-256: `'+sha256(source_bytes[relative])+'`', 'small'))
        text = source_bytes[relative].decode('utf-8-sig')
        story.extend(renderer.code(text.splitlines(), relative))
        story.append(SectionMarker(key, end=True))
    with tempfile.TemporaryDirectory(prefix='u6-pdf-', dir=target.parent) as temporary:
        rendered = Path(temporary)/'rendered.pdf'; embedded = Path(temporary)/'embedded.pdf'
        document = U6Document(str(rendered), title='TP Unidad 6 - Mantenimiento de Food Store',
                              author='Exequiel Arancibia; Joaquin Romero')
        document.multiBuild(story, maxPasses=6)
        for key, _ in short_reports:
            section = document.sections[key]
            if section['start'] != section['end']:
                raise ValueError('One-page limit exceeded: '+key)
        writer = PdfWriter(); writer.clone_document_from_reader(PdfReader(rendered))
        for name, data in attachment_bytes.items(): writer.add_attachment(name, data)
        with embedded.open('wb') as stream: writer.write(stream)
        reader, attachment_checks = verify_embedded(embedded, attachment_bytes)
        qa = {'pdf': target.name, 'pages': len(reader.pages),
              'one_page_sections': {key: {**document.sections[key], 'passed': True}
                                    for key, _ in short_reports},
              'dry_measurements': measurements, 'attachments': attachment_checks,
              'attachment_hashes_verified': True, 'source_count': len(sources),
              'attachment_count': len(attachment_bytes),
              'visual_line_wrapping': renderer.wrapped_lines,
              'visual_qa': 'Pending inspection of all rendered final pages',
              'scope': 'Layout and byte-integrity checks only; no database execution or human approval inferred'}
        pdf_bytes = embedded.read_bytes(); qa['pdf_sha256'] = sha256(pdf_bytes)
        target.write_bytes(pdf_bytes)
    qa_path = target.with_name(target.stem+'_qa.json')
    qa_path.write_bytes((json.dumps(qa, ensure_ascii=False, indent=2)+'\n').encode('utf-8'))
    print(json.dumps({'output': str(target), 'qa': str(qa_path), 'pages': qa['pages'],
                      'source_count': len(sources), 'attachment_count': len(attachment_bytes),
                      'attachment_hashes_verified': True,
                      'one_page_limits_passed': True}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\tools\opencode_consulta.py

SHA256 original: 7baa7379b6d90be470ef62d393744e588b1997e7ae3ab79fa40191690b49b1c6
SHA256 saneado: 8f5ae01928127a6d906190551ef9b8b3539a85c34e57caac20e6226482932d73

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Run an actual, tool-denied OpenCode consultation and retain its provenance.

Only supply material already sanitized for disclosure. The complete event stream
and diagnostic output are stored outside this repository; the repository receives
the exact prompt, answer text, and non-secret run metadata. This program does not
execute generated SQL and does not represent technical review as human approval.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


REPOSITORY = Path(__file__).resolve().parents[1]
TASK_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_EXECUTABLE = Path(
    r"C:\Users\ASPIRE LITE 16\AppData\Roaming\npm\node_modules\opencode-ai\bin\opencode.exe"
)
DEFAULT_MODEL = "openai/gpt-6.1-sol"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def parse_events(raw: str) -> tuple[list[dict], list[str]]:
    events, unparsable = [], []
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            unparsable.append(line)
        else:
            if isinstance(event, dict):
                events.append(event)
            else:
                unparsable.append(line)
    return events, unparsable


def extract_answer(events: list[dict]) -> str:
    chunks = []
    for event in events:
        if event.get("type") != "text":
            continue
        part = event.get("part", {})
        text = part.get("text") if isinstance(part, dict) else None
        if isinstance(text, str) and text.strip():
            chunks.append(text)
    return "\n\n".join(chunks).strip()


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True,
                        help="Artifact label, for example d or a_revision")
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--file", dest="attachments", type=Path,
                        action="append", default=[],
                        help="Previously sanitized context attachment; repeatable")
    parser.add_argument("--executable", type=Path, default=DEFAULT_EXECUTABLE)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--working-dir", type=Path,
                        default=TASK_ROOT / "work/unidad6/opencode")
    parser.add_argument("--output-dir", type=Path,
                        default=REPOSITORY / "docs/ia")
    parser.add_argument("--private-dir", type=Path,
                        default=TASK_ROOT / "work/unidad6/private/opencode")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--retry-failed", action="store_true",
                        help="Retry an unsuccessful consultation, preserving its metadata privately")
    return parser.parse_args()


def main() -> int:
    args = arguments()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", args.prefix):
        raise SystemExit("Invalid artifact prefix")
    if is_within(args.private_dir, REPOSITORY):
        raise SystemExit("Raw events must be stored outside the deliverable repository")
    if not args.executable.is_file() or not args.prompt_file.is_file():
        raise SystemExit("Missing executable or prompt file")
    for attachment in args.attachments:
        if not attachment.is_file():
            raise SystemExit("A sanitized attachment does not exist")
    if args.timeout < 1:
        raise SystemExit("Timeout must be positive")

    prompt = args.prompt_file.read_text(encoding="utf-8")
    if not prompt.strip():
        raise SystemExit("Empty prompt")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.private_dir.mkdir(parents=True, exist_ok=True)
    args.working_dir.mkdir(parents=True, exist_ok=True)
    prompt_output = args.output_dir / f"{args.prefix}_prompt.txt"
    answer_output = args.output_dir / f"{args.prefix}_respuesta.md"
    metadata_output = args.output_dir / f"{args.prefix}_metadatos.json"
    prior_attempts = []
    if any(path.exists() for path in (answer_output, metadata_output)):
        if not args.retry_failed or answer_output.exists() or not metadata_output.exists():
            raise SystemExit("Answer/metadata already exist; use a new prefix for a new consultation")
        previous = json.loads(metadata_output.read_text(encoding="utf-8"))
        if previous.get("status") != "failed":
            raise SystemExit("A completed consultation cannot be retried under the same prefix")
        prior_attempts = previous.get("prior_failed_attempts", []) + [{
            key: previous.get(key) for key in (
                "started_at_utc", "finished_at_utc", "returncode", "timed_out",
                "event_count", "error_event_count", "raw_jsonl_sha256", "status"
            )
        }]
        failed_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        (args.private_dir / f"{args.prefix}_{failed_id}_previous_metadata.json").write_text(
            json.dumps(previous, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    if prompt_output.resolve() != args.prompt_file.resolve():
        prompt_output.write_text(prompt, encoding="utf-8")

    # Feed immutable byte-for-byte snapshots, so later SQL corrections cannot
    # replace the evidence of what the assistant actually received.
    snapshots = []
    if args.attachments:
        attachment_dir = args.output_dir / f"{args.prefix}_adjuntos"
        attachment_dir.mkdir(parents=True, exist_ok=True)
        for index, original in enumerate(args.attachments, 1):
            snapshot = attachment_dir / f"{index:02d}_{original.name}"
            source = original.read_bytes()
            if snapshot.exists() and snapshot.read_bytes() != source:
                raise SystemExit("An existing attachment snapshot differs; use a new consultation prefix")
            if not snapshot.exists():
                snapshot.write_bytes(source)
            snapshots.append((original, snapshot))

    environment = os.environ.copy()
    environment["OPENCODE_CONFIG_CONTENT"] = json.dumps({"permission": "deny"})
    version = subprocess.run(
        [str(args.executable), "--version"], env=environment,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        shell=False, timeout=30, check=False,
    )
    if version.returncode != 0:
        raise SystemExit("Unable to read installed OpenCode version")
    command = [str(args.executable), "run", prompt, "--pure", "--agent", "plan",
               "--format", "json", "--model", args.model,
               "--dir", str(args.working_dir.resolve())]
    for original, snapshot in snapshots:
        command.extend(["--file", str(snapshot.resolve())])

    started = utc_now()
    identifier = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    raw_output = args.private_dir / f"{args.prefix}_{identifier}.jsonl"
    raw_errors = args.private_dir / f"{args.prefix}_{identifier}.stderr.txt"
    timed_out = False
    try:
        completed = subprocess.run(
            command, env=environment, capture_output=True, text=True,
            encoding="utf-8", errors="replace", shell=False,
            timeout=args.timeout, check=False,
        )
        stdout, stderr, returncode = (
            completed.stdout, completed.stderr, completed.returncode
        )
    except subprocess.TimeoutExpired as error:
        timed_out = True
        stdout = error.stdout or ""
        stderr = error.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        returncode = None
    raw_output.write_text(stdout, encoding="utf-8")
    raw_errors.write_text(stderr, encoding="utf-8")
    events, invalid = parse_events(stdout)
    answer = extract_answer(events)
    errors = [event for event in events if event.get("type") == "error"]
    tool_events = [event for event in events
                   if event.get("type") in {"tool_use", "tool"}]
    successful = returncode == 0 and bool(answer) and not errors and not timed_out
    if answer:
        answer_output.write_text(answer + "\n", encoding="utf-8")
    attachments = []
    for original, snapshot in snapshots:
        item = {"name": original.name, "sha256": sha256(snapshot)}
        if is_within(snapshot, REPOSITORY):
            item["repository_path"] = snapshot.resolve().relative_to(REPOSITORY).as_posix()
        if is_within(original, REPOSITORY):
            item["source_path_at_consultation"] = original.resolve().relative_to(REPOSITORY).as_posix()
        attachments.append(item)
    metadata = {
        "tool": "OpenCode",
        "installed_version": version.stdout.strip(),
        "requested_model": args.model,
        "agent": "plan", "pure": True,
        "permission_config": {"permission": "deny"},
        "started_at_utc": started, "finished_at_utc": utc_now(),
        "prompt_sha256": sha256(prompt_output),
        "attachments": attachments,
        "returncode": returncode, "timed_out": timed_out,
        "event_count": len(events), "unparsed_line_count": len(invalid),
        "error_event_count": len(errors), "tool_event_count": len(tool_events),
        "answer_sha256": sha256(answer_output) if answer_output.exists() else None,
        "raw_jsonl_sha256": sha256(raw_output),
        "raw_event_storage": "Private work directory outside deliverable repository",
        "status": "completed" if successful else "failed",
        "prior_failed_attempts": prior_attempts,
        "sql_executed": False,
        "human_validation": "Pending; this consultation does not establish human approval",
    }
    metadata_output.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # Never print raw output, errors, authentication material, or environment.
    print(json.dumps({"prefix": args.prefix, "status": metadata["status"],
                      "model": args.model, "event_count": len(events),
                      "answer_characters": len(answer)}, ensure_ascii=False))
    return 0 if successful else 1


if __name__ == "__main__":
    sys.exit(main())

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\tools\ps_common.ps1

SHA256 original: bc5a4e87493312e4954d2e4849d756576fe6566c0256e902b4d770f1add81392
SHA256 saneado: f2ae054f5a0c31e696a9834978f27b4ff9e0b28d4ebf50c3f88ec5e6e906761b

`````ps1
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
# Funciones comunes factorizadas de la propuesta real OpenCode u6_generacion.
# Integracion/revision automatica Codex; no equivalen a prueba de ejecucion.
foreach ($key in @('PGHOSTADDR','PGSERVICE','PGSERVICEFILE','PGOPTIONS','PGPASSWORD')) {
    Remove-Item -LiteralPath "Env:$key" -ErrorAction SilentlyContinue
}
$env:PGCLIENTENCODING = 'UTF8'
function Log([string]$Text) {
    $line = "$([DateTimeOffset]::UtcNow.ToString('o')) $Text"
    if ($null -ne $log) { $log.WriteLine($line) }
    [Console]::Error.WriteLine($line)
}
function New-Writer([string]$Path) {
    $stream = [IO.File]::Open($Path, 'CreateNew', 'Write', 'None')
    [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
}
function Assert-Private([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Ruta redirigida.' }
    $allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
    foreach ($ace in (Get-Acl -LiteralPath $Path).Access) {
        $sid = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($ace.AccessControlType -eq 'Allow' -and $sid -notin $allowed) { throw 'ACL no privada.' }
    }
    $parent = if ($item.PSIsContainer) { $item } else { $item.Directory }
    for ($d=$parent; $null -ne $d; $d=$d.Parent) {
        if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) {
            throw 'Material privado dentro de Git o ruta redirigida.'
        }
    }
}
function Pg([string]$Name, [string[]]$Arguments) {
    $output = & (Join-Path $PgBin "$Name.exe") @Arguments 2>$null
    $code = $LASTEXITCODE
    if ($code -ne 0) { Log "FAILED native=$Name code=$code"; throw "${Name}: codigo $code" }
    $output
}
function Assert-Baseline($Value) {
    $tables = @('categoria','producto','usuario','pedido','detalle_pedido')
    $sets = @{ counts=$tables; fingerprints=$tables; invalid=@('productos','detalles') }
    if ($Value -isnot [Collections.IDictionary] -or $Value.Count -ne 3) { throw 'JSON base invalido.' }
    foreach ($section in $sets.Keys) {
        $part = $Value[$section]
        if ($part -isnot [Collections.IDictionary] -or $part.Count -ne $sets[$section].Count) {
            throw 'Claves invalidas.'
        }
        foreach ($key in $sets[$section]) {
            if (-not $part.Contains($key)) { throw 'Falta clave.' }
            $v = $part[$key]
            if ($section -eq 'fingerprints') {
                if ($v -isnot [string] -or $v -cnotmatch '^[0-9a-f]{32}$') { throw 'Huella invalida.' }
            } elseif (($v -isnot [long] -and $v -isnot [int]) -or $v -lt 0 -or
                      ($section -eq 'invalid' -and $v -ne 0)) { throw 'Conteo o integridad invalidos.' }
        }
    }
}
function Assert-Isolation([string[]]$PsqlArguments, [string]$RoleLiterals) {
    $check = @'
SELECT (d.datconnlimit=0 AND NOT EXISTS (
 SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname IN (__LITERALS__)
 AND (pg_catalog.has_database_privilege(r.rolname,d.datname,'CONNECT')
   OR pg_catalog.has_database_privilege(r.rolname,d.datname,'TEMPORARY'))
) AND NOT EXISTS (
 SELECT 1 FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_namespace n
 WHERE r.rolname IN (__LITERALS__) AND n.nspname !~ '^pg_'
 AND n.nspname<>'information_schema'
 AND (pg_catalog.has_schema_privilege(r.rolname,n.oid,'USAGE')
   OR pg_catalog.has_schema_privilege(r.rolname,n.oid,'CREATE'))
) AND NOT EXISTS (
 SELECT 1 FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE r.rolname IN (__LITERALS__) AND n.nspname !~ '^pg_'
 AND n.nspname<>'information_schema'
 AND pg_catalog.has_function_privilege(r.rolname,p.oid,'EXECUTE')
))::int FROM pg_catalog.pg_database d WHERE d.datname=current_database();
'@
    $check = $check.Replace('__LITERALS__',$RoleLiterals)
    if ((Pg 'psql' ($PsqlArguments + @('-c',$check)) | Out-String).Trim() -ne '1') {
        throw 'Aislamiento final no verificado.'
    }
}
function New-RunToken {
    $stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ',
        [Globalization.CultureInfo]::InvariantCulture)
    "$stamp`_$([guid]::NewGuid().ToString('N'))"
}
function Assert-Clients([string[]]$Names) {
    foreach ($name in $Names) {
        $version = Pg $name @('--version') | Out-String
        if ($version -notmatch '\(PostgreSQL\) 17(?:\.|\s|$)') { throw 'Se requieren clientes 17.' }
    }
}
function Read-BackupManifest {
    $candidates = @(foreach ($file in Get-ChildItem -LiteralPath $LogDir -Filter '*.manifest.json' -File) {
        Assert-Private $file.FullName
        $m = Get-Content -LiteralPath $file.FullName -Raw |
            ConvertFrom-Json -AsHashtable -DateKind String
        if ($m.status -ceq 'SUCCESS') {
            $end = [DateTimeOffset]::ParseExact($m.endUtc,'o',[Globalization.CultureInfo]::InvariantCulture)
            [pscustomobject]@{ Manifest=$m; End=$end }
        }
    })
    if ($candidates.Count -eq 0) { throw 'No hay manifiesto exitoso.' }
    $chosen = $candidates | Sort-Object End -Descending | Select-Object -First 1
    $m = $chosen.Manifest
    $start = [DateTimeOffset]::ParseExact($m.startUtc,'o',[Globalization.CultureInfo]::InvariantCulture)
    if ($m.database -cne 'foodstore' -or $start.Offset -ne [TimeSpan]::Zero -or
        $chosen.End.Offset -ne [TimeSpan]::Zero -or $chosen.End -lt $start -or
        $chosen.End -gt [DateTimeOffset]::UtcNow) { throw 'Metadatos temporales invalidos.' }
    $pattern = '^foodstore_[0-9]{8}T[0-9]{13}Z_[0-9a-f]{32}\.dump$'
    if ($m.file -isnot [string] -or $m.file -cnotmatch $pattern) { throw 'Nombre no permitido.' }
    if (($m.size -isnot [long] -and $m.size -isnot [int]) -or $m.size -le 0 -or
        $m.sha256 -isnot [string] -or $m.sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Tamano o hash invalido.'
    }
    Assert-Baseline $m.baseline
    $dump = Join-Path $BackupDir $m.file
    Assert-Private $dump
    $hash = (Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $dump).Length -ne $m.size -or $hash -cne $m.sha256) {
        throw 'Respaldo alterado.'
    }
    Pg 'pg_restore' @('--list',$dump) | Out-Null
    [pscustomobject]@{ Manifest=$m; Start=$start; Dump=$dump }
}

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\validaciones.sql

SHA256 original: 8198129eaf53a1e96e432a02c0659f5c4eb7d094de2e05ad9deb022e1cb53849
SHA256 saneado: e94a54cf47471f2bf6f5ccd2b60ca6d7a4c4ddcb89cdf7622b1b2d1bc3e185e3

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Unidad 6 - Food Store. Exequiel Arancibia / Joaquin Romero.
-- Implementacion tecnica: Codex. Ejecutar con psql -X -w -A -t
-- -v ON_ERROR_STOP=1 -d foodstore[..._restore_test] -f validaciones.sql.
-- stdout: UN objeto JSON con counts, fingerprints, invalid. Sin filas ni PII.
-- La guia llama cliente a la entidad que aqui conserva public.usuario.
\set ON_ERROR_STOP on
\set QUIET 1
\pset pager off

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL TIME ZONE 'America/Argentina/Buenos_Aires';
SET LOCAL DateStyle = 'ISO, YMD';
SET LOCAL application_name = 'u6_validaciones';

DO $base_correcta$
BEGIN
    IF pg_catalog.current_database() NOT IN ('foodstore','foodstore_restore_test') THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'validaciones.sql requiere foodstore o foodstore_restore_test';
    END IF;
END
$base_correcta$;

-- Una instantanea por ejecucion evita mezclar conteos de varios instantes.
-- El orquestador debe evitar escritores entre baseline y snapshot del dump,
-- o compartir expresamente un snapshot exportado. Este archivo no lo presume.
-- Las huellas siguen U5: MD5 de la concatenacion ordenada de MD5 de cada fila
-- completa en JSON. Son checksums de conservacion, no anonimato ni firma.
-- Se fija zona/DateStyle para que timestamps tengan la misma representacion.
WITH categorias AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.categoria AS t
), productos AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.count(*) FILTER (WHERE t.precio < 0 OR t.stock < 0) AS invalidos,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.producto AS t
), usuarios AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.usuario AS t
), pedidos AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.pedido AS t
), detalles AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.count(*) FILTER (WHERE t.cantidad <= 0 OR t.precio_unitario < 0) AS invalidos,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),''
               ORDER BY t.pedido_id,t.producto_id),'')) AS huella
    FROM public.detalle_pedido AS t
)
SELECT pg_catalog.jsonb_build_object(
    'counts', pg_catalog.jsonb_build_object(
        'categoria',c.n,'producto',pr.n,'usuario',u.n,'pedido',pe.n,'detalle_pedido',d.n),
    'fingerprints', pg_catalog.jsonb_build_object(
        'categoria',c.huella,'producto',pr.huella,'usuario',u.huella,
        'pedido',pe.huella,'detalle_pedido',d.huella),
    'invalid', pg_catalog.jsonb_build_object('productos',pr.invalidos,'detalles',d.invalidos)
) AS validacion
FROM categorias AS c CROSS JOIN productos AS pr CROSS JOIN usuarios AS u
CROSS JOIN pedidos AS pe CROSS JOIN detalles AS d;

COMMIT;

-- No agregar metadata variable a este JSON: los scripts registran fecha/base
-- y comparan los cinco counts/fingerprints y los dos ceros de forma explicita.
-- precio, stock, cantidad y precio_unitario son NOT NULL en el modelo real;
-- las condiciones invalid conservan exactamente los controles de la guia.

`````
