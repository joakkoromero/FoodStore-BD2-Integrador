# Exequiel Arancibia / Joaquin Romero - continuidad de TP1 a TP5.
# Crea una base nueva; createdb falla si ya existe. No borra otras bases.
param(
    [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$Servidor = '127.0.0.1',
    [int]$Puerto = 5432,
    [string]$Usuario = 'postgres'
)
$ErrorActionPreference = 'Stop'
$env:PGCLIENTENCODING = 'UTF8'
$baseU4 = 'foodstore_u4_arancibia_romero'
$archivosU4 = $PSScriptRoot
$copiaU4 = Join-Path $archivosU4 'antecedentes\respaldo_pre_tp4.dump'
$hashU4 = (Get-FileHash -LiteralPath $copiaU4 -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hashU4 -ne 'f53af18eac3da8de40114f63daaea8ccddae528db688b68e6740c8e31fc01871') {
    throw 'El respaldo no coincide con el original adjunto del TP4.'
}
& (Join-Path $PgBin 'createdb.exe') -h $Servidor -p $Puerto -U $Usuario $baseU4
if ($LASTEXITCODE -ne 0) { throw 'No se creo la base nueva; no continuar.' }
& (Join-Path $PgBin 'pg_restore.exe') -h $Servidor -p $Puerto -U $Usuario -d $baseU4 --no-owner --no-privileges --exit-on-error $copiaU4
if ($LASTEXITCODE -ne 0) { throw 'Fallo la restauracion del respaldo.' }
foreach ($nombreU4 in @('antecedentes\indices_tp4.sql', 'antecedentes\indices_tp5.sql', 'antecedentes\views_tp5.sql', '01_actividad_del_dia.sql')) {
    & (Join-Path $PgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -h $Servidor -p $Puerto -U $Usuario -d $baseU4 -f (Join-Path $archivosU4 $nombreU4)
    if ($LASTEXITCODE -ne 0) { throw "Fallo el archivo $nombreU4" }
}
Write-Output 'Base heredada preparada. Ejecutar ahora los dos scripts de Unidad 4.'
