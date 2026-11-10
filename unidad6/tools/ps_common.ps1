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
