## `run_backup_job.ps1`

```powershell
#requires -Version 7.5
#requires -PSEdition Core

[CmdletBinding(DefaultParameterSetName = 'File')]
param(
    [Parameter(Mandatory)]
    [string] $ConfigPath,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [string] $ResultPath,

    [Parameter(Mandatory, ParameterSetName = 'Directory')]
    [string] $ResultDirectory,

    [switch] $ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# El esquema de manifiesto esperado se documenta en README.md.
# No se intenta adivinar ni convertir formatos internos de U6.

$script:CurrentSid = $null
$script:AllowedSids = @()
$startedUtc = [DateTimeOffset]::UtcNow
$nativeExitCode = $null
$resultTarget = $null
$resultLocationValidated = $false
$resultWriteAttempted = $false
$failureCode = 'VALIDATION_FAILED'

function Get-NormalizedLocalPath {
    param([Parameter(Mandatory)][string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path.Contains('"') -or
        $Path -match '[\x00-\x1f]' -or
        $Path -notmatch '^[A-Za-z]:\\' -or
        $Path.Substring(2).Contains(':')) {
        throw 'INVALID_LOCAL_PATH'
    }

    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) {
        $full = $full.TrimEnd('\')
    }

    return $full
}

function Assert-PathChain {
    param([Parameter(Mandatory)][string] $Path)

    $cursor = $Path

    while ($true) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop

        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'REPARSE_POINT_NOT_ALLOWED'
        }

        if ($item.Name -ieq '.git') {
            throw 'GIT_LOCATION_NOT_ALLOWED'
        }

        if ($item.PSIsContainer) {
            # También rechaza repositorios cuyo .git es un archivo de worktree.
            $gitMarker = Join-Path $item.FullName '.git'
            if (Test-Path -LiteralPath $gitMarker -ErrorAction Stop) {
                throw 'GIT_LOCATION_NOT_ALLOWED'
            }
        }

        $parent = [IO.Directory]::GetParent($item.FullName)
        if ($null -eq $parent) {
            break
        }
        $cursor = $parent.FullName
    }
}

function Assert-PrivateItem {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][bool] $Directory,
        [bool] $RequireProtected = $true
    )

    Assert-PathChain -Path $Path
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

    if ([bool]$item.PSIsContainer -ne $Directory) {
        throw 'UNEXPECTED_ITEM_TYPE'
    }

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $owner = $acl.GetOwner(
        [Security.Principal.SecurityIdentifier]
    ).Value

    if ($owner -notin $script:AllowedSids) {
        throw 'UNTRUSTED_OWNER'
    }

    if ($RequireProtected -and -not $acl.AreAccessRulesProtected) {
        throw 'ACL_INHERITANCE_NOT_DISABLED'
    }

    $rules = $acl.GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    )

    foreach ($rule in $rules) {
        if ($rule.AccessControlType -ne
            [Security.AccessControl.AccessControlType]::Allow) {
            continue
        }

        $sid = $rule.IdentityReference.Value

        if ($sid -eq 'S-1-3-4') {
            if ($owner -ne $script:CurrentSid) {
                throw 'OWNER_RIGHTS_WITH_UNTRUSTED_OWNER'
            }
            continue
        }

        if ($sid -notin $script:AllowedSids) {
            throw 'ACL_GRANTS_OTHER_IDENTITIES'
        }
    }
}

function Read-UtcInstant {
    param([Parameter(Mandatory)][string] $Value)

    if ($Value -notmatch
        '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|\+00:00)$') {
        throw 'UTC_INSTANT_REQUIRED'
    }

    $instant = [DateTimeOffset]::MinValue
    $parsed = [DateTimeOffset]::TryParse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$instant
    )

    if (-not $parsed -or $instant.Offset -ne [TimeSpan]::Zero) {
        throw 'INVALID_UTC_INSTANT'
    }

    return $instant
}

function Assert-LiveWindow {
    param([Parameter(Mandatory)][DateTimeOffset] $Expires)

    $now = [DateTimeOffset]::UtcNow
    if ($Expires -le $now -or $Expires -gt $now.AddMinutes(60)) {
        throw 'WINDOW_NOT_VALID'
    }
}

function Invoke-PrivateProcess {
    param(
        [Parameter(Mandatory)][string] $Executable,
        [Parameter(Mandatory)][string[]] $ArgumentList,
        [Parameter(Mandatory)]
        [Collections.Generic.Dictionary[string, string]] $Environment,
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [int] $TimeoutSeconds = 30
    )

    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true

    foreach ($argument in $ArgumentList) {
        [void]$info.ArgumentList.Add($argument)
    }

    # No heredar redirecciones libpq del proceso invocante.
    foreach ($name in @($info.Environment.Keys)) {
        if ($name.StartsWith('PG', [StringComparison]::OrdinalIgnoreCase)) {
            [void]$info.Environment.Remove($name)
        }
    }

    foreach ($entry in $Environment.GetEnumerator()) {
        $info.Environment[$entry.Key] = $entry.Value
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info

    try {
        if (-not $process.Start()) {
            throw 'PROCESS_START_FAILED'
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
            }
            catch {
                # No divulgar diagnósticos nativos.
            }
            throw 'PROCESS_TIMEOUT'
        }

        # Leer el código inmediatamente después de terminar el proceso nativo.
        $exitCode = $process.ExitCode
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        [void]$stderrTask.GetAwaiter().GetResult()

        return [pscustomobject]@{
            ExitCode = $exitCode
            Stdout   = $stdout
        }
    }
    finally {
        $process.Dispose()
    }
}

function Write-NewJson {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][object] $Value
    )

    $json = ConvertTo-Json -InputObject $Value -Depth 20
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)

    $stream = [IO.FileStream]::new(
        $Path,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )

    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
}

function Get-SafeBaseline {
    param([Parameter(Mandatory)][Collections.IDictionary] $Baseline)

    $required = @('counts', 'invalid', 'fingerprints')
    if ($Baseline.Count -ne $required.Count) {
        throw 'UNSUPPORTED_BASELINE_SCHEMA'
    }

    $safe = [ordered]@{}

    foreach ($section in $required) {
        if (-not $Baseline.Contains($section) -or
            $Baseline[$section] -isnot [Collections.IDictionary]) {
            throw 'UNSUPPORTED_BASELINE_SCHEMA'
        }

        $values = [ordered]@{}
        foreach ($entry in $Baseline[$section].GetEnumerator()) {
            $name = [string]$entry.Key

            if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_.]{0,127}$') {
                throw 'UNSAFE_BASELINE_LABEL'
            }

            if ($section -eq 'fingerprints') {
                if ($entry.Value -isnot [string] -or
                    $entry.Value -notmatch '^[A-Fa-f0-9]{64}$') {
                    throw 'INVALID_FINGERPRINT'
                }
                $values[$name] = $entry.Value.ToLowerInvariant()
            }
            else {
                if (($entry.Value -isnot [long] -and
                     $entry.Value -isnot [int] -and
                     $entry.Value -isnot [System.Numerics.BigInteger]) -or
                    $entry.Value -lt 0 -or
                    $entry.Value -gt [long]::MaxValue) {
                    throw 'INVALID_BASELINE_COUNT'
                }
                $values[$name] = [long]$entry.Value
            }
        }

        $safe[$section] = $values
    }

    return $safe
}

try {
    if (-not $IsWindows) {
        throw 'WINDOWS_REQUIRED'
    }

    $script:CurrentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $script:AllowedSids = @(
        $script:CurrentSid,
        'S-1-5-18',
        'S-1-5-32-544'
    )

    # Validar primero el destino: nunca escribir resultados en una ubicación
    # que no haya superado los controles de privacidad.
    if ($PSCmdlet.ParameterSetName -eq 'Directory') {
        $ResultDirectory = Get-NormalizedLocalPath -Path $ResultDirectory
        Assert-PrivateItem -Path $ResultDirectory -Directory $true

        $resultName = 'job-{0}-{1}.json' -f (
            $startedUtc.ToString('yyyyMMddTHHmmssfffffffZ')
        ), ([guid]::NewGuid().ToString('N'))

        $resultTarget = Join-Path $ResultDirectory $resultName
    }
    else {
        $resultTarget = Get-NormalizedLocalPath -Path $ResultPath
        $resultParent = [IO.Path]::GetDirectoryName($resultTarget)
        Assert-PrivateItem -Path $resultParent -Directory $true
    }

    if (Test-Path -LiteralPath $resultTarget) {
        throw 'RESULT_ALREADY_EXISTS'
    }
    $resultLocationValidated = $true

    $ConfigPath = Get-NormalizedLocalPath -Path $ConfigPath
    Assert-PrivateItem -Path $ConfigPath -Directory $false

    $configItem = Get-Item -LiteralPath $ConfigPath -Force
    if ($configItem.Length -gt 65536) {
        throw 'CONFIG_TOO_LARGE'
    }

    $configText = [IO.File]::ReadAllText($ConfigPath)
    $expectedKeys = @(
        'U6Root', 'PgBin', 'DbUser', 'HostName',
        'Port', 'PassFile', 'BackupWorkDir', 'WindowExpiresUtc'
    )

    # JsonDocument permite detectar claves repetidas antes de convertir.
    $document = [Text.Json.JsonDocument]::Parse($configText)
    try {
        if ($document.RootElement.ValueKind -ne
            [Text.Json.JsonValueKind]::Object) {
            throw 'CONFIG_MUST_BE_OBJECT'
        }

        $properties = @($document.RootElement.EnumerateObject())
        if ($properties.Count -ne $expectedKeys.Count) {
            throw 'INVALID_CONFIG_KEYS'
        }

        $seen = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )

        foreach ($property in $properties) {
            if ($property.Name -cnotin $expectedKeys -or
                -not $seen.Add($property.Name)) {
                throw 'INVALID_CONFIG_KEYS'
            }

            if ($property.Name -ceq 'Port') {
                if ($property.Value.ValueKind -ne
                    [Text.Json.JsonValueKind]::Number) {
                    throw 'PORT_MUST_BE_INTEGER'
                }
            }
            elseif ($property.Value.ValueKind -ne
                    [Text.Json.JsonValueKind]::String) {
                throw 'CONFIG_STRING_REQUIRED'
            }
        }
    }
    finally {
        $document.Dispose()
    }

    $config = ConvertFrom-Json -InputObject $configText `
        -AsHashtable -DateKind String

    if ($config['HostName'] -cne '127.0.0.1' -or
        $config['DbUser'] -cne 'u5_bootstrap') {
        throw 'DATABASE_ENDPOINT_NOT_ALLOWED'
    }

    if (($config['Port'] -isnot [long] -and
         $config['Port'] -isnot [int]) -or
        $config['Port'] -lt 1 -or $config['Port'] -gt 65535) {
        throw 'INVALID_PORT'
    }

    $expires = Read-UtcInstant -Value $config['WindowExpiresUtc']
    Assert-LiveWindow -Expires $expires

    foreach ($key in @('U6Root', 'PgBin', 'PassFile', 'BackupWorkDir')) {
        $config[$key] = Get-NormalizedLocalPath -Path $config[$key]
    }

    Assert-PrivateItem -Path $config['PassFile'] -Directory $false
    Assert-PrivateItem -Path $config['BackupWorkDir'] -Directory $true

    foreach ($directory in @($config['U6Root'], $config['PgBin'])) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw 'DEPENDENCY_DIRECTORY_MISSING'
        }
    }

    $backupScript = Join-Path $config['U6Root'] 'backup_foodstore.ps1'
    foreach ($dependency in @(
        $backupScript,
        (Join-Path $config['U6Root'] 'validaciones.sql'),
        (Join-Path $config['U6Root'] 'tools\ps_common.ps1')
    )) {
        if (-not (Test-Path -LiteralPath $dependency -PathType Leaf)) {
            throw 'U6_DEPENDENCY_MISSING'
        }
    }

    $pwsh = Get-NormalizedLocalPath -Path (Join-Path $PSHOME 'pwsh.exe')
    if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) {
        throw 'PWSH_MISSING'
    }

    $environment = [Collections.Generic.Dictionary[string, string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $environment['PGPASSFILE'] = $config['PassFile']
    $environment['PGCONNECT_TIMEOUT'] = '10'
    $environment['PGHOST'] = '127.0.0.1'
    $environment['PGPORT'] = [string]$config['Port']
    $environment['PGUSER'] = 'u5_bootstrap'
    $environment['PGDATABASE'] = 'foodstore'
    $environment['PGAPPNAME'] = 'FoodStore-TPI-Lab'

    foreach ($client in @('psql.exe', 'pg_dump.exe', 'pg_restore.exe')) {
        $executable = Join-Path $config['PgBin'] $client
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw 'POSTGRESQL_CLIENT_MISSING'
        }

        $versionResult = Invoke-PrivateProcess `
            -Executable $executable `
            -ArgumentList @('--version') `
            -Environment $environment `
            -WorkingDirectory $config['U6Root']

        $nativeExitCode = $versionResult.ExitCode
        if ($nativeExitCode -ne 0 -or
            $versionResult.Stdout -notmatch '\(PostgreSQL\)\s+17(?:\.|\s|$)') {
            throw 'POSTGRESQL_17_REQUIRED'
        }
    }

    if ($ValidateOnly) {
        # No conexión SQL, backup, resultado ni registro de tareas.
        exit 0
    }

    $failureCode = 'SESSION_PRECHECK_FAILED'
    Assert-LiveWindow -Expires $expires

    $psql = Join-Path $config['PgBin'] 'psql.exe'
    $sessionQuery = @'
SELECT count(*)
FROM pg_catalog.pg_stat_activity
WHERE datname = 'foodstore'
  AND backend_type = 'client backend'
  AND pid <> pg_backend_pid();
'@

    $sessionResult = Invoke-PrivateProcess `
        -Executable $psql `
        -ArgumentList @(
            '-X', '-w',
            '-h', '127.0.0.1',
            '-p', [string]$config['Port'],
            '-U', 'u5_bootstrap',
            '-d', 'foodstore',
            '-A', '-t',
            '-v', 'ON_ERROR_STOP=1',
            '-c', $sessionQuery
        ) `
        -Environment $environment `
        -WorkingDirectory $config['U6Root']

    $nativeExitCode = $sessionResult.ExitCode
    if ($nativeExitCode -ne 0 -or $sessionResult.Stdout.Trim() -cne '0') {
        throw 'OTHER_CLIENTS_OR_PRECHECK_ERROR'
    }

    $previousJson = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($file in Get-ChildItem -LiteralPath $config['BackupWorkDir'] `
            -Filter '*.json' -File -Recurse -Force) {
        [void]$previousJson.Add($file.FullName)
    }

    # Revalidación inmediatamente antes de pasar -ConfirmNoWrites.
    # La consulta anterior es una observación, no un cerrojo.
    Assert-LiveWindow -Expires $expires
    Assert-PrivateItem -Path $ConfigPath -Directory $false
    Assert-PrivateItem -Path $config['PassFile'] -Directory $false
    Assert-PrivateItem -Path $config['BackupWorkDir'] -Directory $true

    $failureCode = 'BACKUP_PROCESS_FAILED'
    $backupResult = Invoke-PrivateProcess `
        -Executable $pwsh `
        -ArgumentList @(
            '-NoLogo', '-NoProfile', '-NonInteractive',
            '-File', $backupScript,
            '-HostName', '127.0.0.1',
            '-Port', [string]$config['Port'],
            '-DbUser', 'u5_bootstrap',
            '-PgBin', $config['PgBin'],
            '-WorkDir', $config['BackupWorkDir'],
            '-ConfirmNoWrites'
        ) `
        -Environment $environment `
        -WorkingDirectory $config['U6Root'] `
        -TimeoutSeconds 480

    $nativeExitCode = $backupResult.ExitCode
    if ($nativeExitCode -ne 0) {
        throw 'BACKUP_NONZERO_EXIT'
    }

    $failureCode = 'MANIFEST_VALIDATION_FAILED'
    $candidates = [Collections.Generic.List[object]]::new()

    foreach ($file in Get-ChildItem -LiteralPath $config['BackupWorkDir'] `
            -Filter '*.json' -File -Recurse -Force) {
        if ($previousJson.Contains($file.FullName)) {
            continue
        }

        Assert-PrivateItem -Path $file.FullName -Directory $false `
            -RequireProtected $false

        if ($file.Length -gt 1048576) {
            throw 'NEW_JSON_TOO_LARGE'
        }

        try {
            $manifest = ConvertFrom-Json `
                -InputObject ([IO.File]::ReadAllText($file.FullName)) `
                -AsHashtable -DateKind String
        }
        catch {
            continue
        }

        if ($manifest -isnot [Collections.IDictionary] -or
            -not $manifest.Contains('status') -or
            $manifest['status'] -cne 'SUCCESS') {
            continue
        }

        if (-not $manifest.Contains('startedUtc') -or
            $manifest['startedUtc'] -isnot [string]) {
            throw 'SUCCESS_WITHOUT_VALID_START'
        }

        $manifestStart = Read-UtcInstant -Value $manifest['startedUtc']
        if ($manifestStart -ge $startedUtc -and
            $manifestStart -le [DateTimeOffset]::UtcNow) {
            $candidates.Add($manifest)
        }
    }

    if ($candidates.Count -ne 1) {
        throw 'EXACTLY_ONE_NEW_SUCCESS_REQUIRED'
    }

    $manifest = $candidates[0]
    foreach ($field in @(
        'sourceDatabase', 'backupFile', 'backupBytes',
        'backupSha256', 'baseline'
    )) {
        if (-not $manifest.Contains($field)) {
            throw 'UNSUPPORTED_MANIFEST_SCHEMA'
        }
    }

    if ($manifest['sourceDatabase'] -cne 'foodstore' -or
        $manifest['backupFile'] -isnot [string] -or
        $manifest['backupSha256'] -isnot [string] -or
        $manifest['backupSha256'] -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'INVALID_MANIFEST_METADATA'
    }

    if (($manifest['backupBytes'] -isnot [long] -and
         $manifest['backupBytes'] -isnot [int]) -or
        $manifest['backupBytes'] -le 0) {
        throw 'INVALID_BACKUP_SIZE'
    }

    $declaredBackup = $manifest['backupFile']
    if ([IO.Path]::IsPathFullyQualified($declaredBackup)) {
        $backupPath = Get-NormalizedLocalPath -Path $declaredBackup
    }
    else {
        $backupPath = Get-NormalizedLocalPath -Path (
            Join-Path $config['BackupWorkDir'] $declaredBackup
        )
    }

    $backupPrefix = $config['BackupWorkDir'].TrimEnd('\') + '\'
    if (-not $backupPath.StartsWith(
        $backupPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'BACKUP_OUTSIDE_PRIVATE_DIRECTORY'
    }

    Assert-PrivateItem -Path $backupPath -Directory $false `
        -RequireProtected $false

    $safeBaseline = Get-SafeBaseline -Baseline $manifest['baseline']

    # Mantener abierto sin compartir escritura ni borrado durante la verificación.
    $backupStream = [IO.FileStream]::new(
        $backupPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )

    try {
        $backupBytes = $backupStream.Length
        if ($backupBytes -ne [long]$manifest['backupBytes']) {
            throw 'BACKUP_SIZE_MISMATCH'
        }

        $hashBytes = [Security.Cryptography.SHA256]::HashData($backupStream)
        $backupSha256 = [Convert]::ToHexString($hashBytes).ToLowerInvariant()

        if ($backupSha256 -cne $manifest['backupSha256'].ToLowerInvariant()) {
            throw 'BACKUP_HASH_MISMATCH'
        }
    }
    finally {
        $backupStream.Dispose()
    }

    $summary = [ordered]@{
        status         = 'SUCCESS'
        startedUtc     = $startedUtc.ToString('o')
        finishedUtc    = [DateTimeOffset]::UtcNow.ToString('o')
        sourceDatabase = 'foodstore'
        backupFile     = [IO.Path]::GetFileName($backupPath)
        backupBytes    = $backupBytes
        backupSha256   = $backupSha256
        baseline       = $safeBaseline
        nativeExitCode = $nativeExitCode
    }

    $failureCode = 'RESULT_WRITE_FAILED'
    Assert-PrivateItem -Path ([IO.Path]::GetDirectoryName($resultTarget)) `
        -Directory $true

    $resultWriteAttempted = $true
    Write-NewJson -Path $resultTarget -Value $summary

    Write-Output 'Respaldo verificado; resumen escrito en el destino privado.'
    exit 0
}
catch {
    if (-not $ValidateOnly -and
        $resultLocationValidated -and
        -not $resultWriteAttempted) {
        try {
            Assert-PrivateItem `
                -Path ([IO.Path]::GetDirectoryName($resultTarget)) `
                -Directory $true

            $failureSummary = [ordered]@{
                status         = 'FAILED'
                startedUtc     = $startedUtc.ToString('o')
                finishedUtc    = [DateTimeOffset]::UtcNow.ToString('o')
                sourceDatabase = 'foodstore'
                failureCode    = $failureCode
                nativeExitCode = $nativeExitCode
            }

            $resultWriteAttempted = $true
            Write-NewJson -Path $resultTarget -Value $failureSummary
        }
        catch {
            # Un fallo de escritura nunca se convierte en éxito.
        }
    }

    [Console]::Error.WriteLine(
        'Trabajo rechazado o fallido. No se publican diagnósticos privados.'
    )
    exit 1
}
```

## `crear_tarea_diaria.ps1`

```powershell
#requires -Version 7.5
#requires -PSEdition Core

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ConfigPath,

    [Parameter(Mandatory)]
    [string] $ResultDirectory,

    [Parameter(Mandatory)]
    [string] $XmlPath,

    [string] $TaskName = (
        'FoodStore-TPI-Lab-' + [guid]::NewGuid().ToString('N')
    ),

    # Omitido: próximo horario diario 02:00 con desplazamiento UTC-03.
    # Para el ensayo, pasar explícitamente un instante unos 90 s futuro.
    [string] $FirstRun,

    [switch] $ExportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-ArgumentPath {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)]
        [ValidateSet('File', 'Directory', 'NewFile')]
        [string] $Kind
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path.Contains('"') -or
        $Path -match '[\x00-\x1f]' -or
        $Path -notmatch '^[A-Za-z]:\\' -or
        $Path.Substring(2).Contains(':')) {
        throw 'INVALID_LOCAL_PATH'
    }

    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) {
        $full = $full.TrimEnd('\')
    }

    switch ($Kind) {
        'File' {
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                throw 'FILE_MISSING'
            }
        }
        'Directory' {
            if (-not (Test-Path -LiteralPath $full -PathType Container)) {
                throw 'DIRECTORY_MISSING'
            }
        }
        'NewFile' {
            if (Test-Path -LiteralPath $full) {
                throw 'OUTPUT_ALREADY_EXISTS'
            }

            if (-not (Test-Path -LiteralPath (
                [IO.Path]::GetDirectoryName($full)
            ) -PathType Container)) {
                throw 'OUTPUT_DIRECTORY_MISSING'
            }
        }
    }

    return $full
}

function ConvertTo-QuotedArgument {
    param([Parameter(Mandatory)][string] $Value)

    if ($Value.Contains('"') -or $Value -match '[\x00-\x1f]') {
        throw 'INVALID_ARGUMENT'
    }

    # Escapar barras finales antes de la comilla de cierre según argv Windows.
    $trailing = [regex]::Match($Value, '\\+$').Value
    return '"' + $Value + $trailing + '"'
}

function Set-TaskNode {
    param(
        [Parameter(Mandatory)][xml] $Document,
        [Parameter(Mandatory)][Xml.XmlNamespaceManager] $Namespace,
        [Parameter(Mandatory)][string] $XPath,
        [Parameter(Mandatory)][string] $Value
    )

    $nodes = $Document.SelectNodes($XPath, $Namespace)
    if ($nodes.Count -ne 1) {
        throw 'UNEXPECTED_TEMPLATE'
    }

    $nodes[0].InnerText = $Value
}

try {
    if (-not $IsWindows) {
        throw 'WINDOWS_REQUIRED'
    }

    if ($TaskName -cnotmatch '^FoodStore-TPI-Lab-[0-9a-fA-F]{32}$') {
        throw 'INVALID_TASK_NAME'
    }

    $ConfigPath = Get-ArgumentPath -Path $ConfigPath -Kind File
    $ResultDirectory = Get-ArgumentPath -Path $ResultDirectory -Kind Directory
    $XmlPath = Get-ArgumentPath -Path $XmlPath -Kind NewFile
    $runner = Get-ArgumentPath -Path (
        Join-Path $PSScriptRoot 'run_backup_job.ps1'
    ) -Kind File
    $template = Get-ArgumentPath -Path (
        Join-Path $PSScriptRoot 'tarea_diaria.template.xml'
    ) -Kind File
    $pwsh = Get-ArgumentPath -Path (
        Join-Path $PSHOME 'pwsh.exe'
    ) -Kind File
    $workingDirectory = Get-ArgumentPath -Path $PSScriptRoot -Kind Directory

    # Validar destinos privados y dependencias sin ejecutar SQL ni backup.
    & $pwsh -NoLogo -NoProfile -NonInteractive -File $runner `
        -ConfigPath $ConfigPath -ResultDirectory $ResultDirectory `
        -ValidateOnly *> $null
    $validationExit = $LASTEXITCODE
    if ($validationExit -ne 0) {
        throw 'RUNNER_VALIDATION_FAILED'
    }

    & $pwsh -NoLogo -NoProfile -NonInteractive -File $runner `
        -ConfigPath $ConfigPath -ResultPath $XmlPath `
        -ValidateOnly *> $null
    $validationExit = $LASTEXITCODE
    if ($validationExit -ne 0) {
        throw 'XML_DESTINATION_VALIDATION_FAILED'
    }

    $now = [DateTimeOffset]::UtcNow
    $start = [DateTimeOffset]::MinValue

    if ($PSBoundParameters.ContainsKey('FirstRun')) {
        if ($FirstRun -notmatch
            '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') {
            throw 'EXPLICIT_OFFSET_REQUIRED'
        }

        if (-not [DateTimeOffset]::TryParse(
            $FirstRun,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$start
        )) {
            throw 'INVALID_FIRST_RUN'
        }
    }
    else {
        $offset = [TimeSpan]::FromHours(-3)
        $localNow = $now.ToOffset($offset)
        $start = [DateTimeOffset]::new(
            $localNow.Year,
            $localNow.Month,
            $localNow.Day,
            2, 0, 0,
            $offset
        )

        if ($start -le $now.AddSeconds(30)) {
            $start = $start.AddDays(1)
        }
    }

    if ($start -le $now.AddSeconds(30)) {
        throw 'FIRST_RUN_MUST_BE_FUTURE'
    }

    $readerSettings = [Xml.XmlReaderSettings]::new()
    $readerSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $readerSettings.XmlResolver = $null

    $reader = [Xml.XmlReader]::Create($template, $readerSettings)
    $xml = [Xml.XmlDocument]::new()
    $xml.XmlResolver = $null

    try {
        $xml.Load($reader)
    }
    finally {
        $reader.Dispose()
    }

    $namespace = [Xml.XmlNamespaceManager]::new($xml.NameTable)
    $namespace.AddNamespace(
        't',
        'http://schemas.microsoft.com/windows/2004/02/mit/task'
    )

    if ($xml.SelectNodes('/t:Task/t:Actions/*', $namespace).Count -ne 1 -or
        $xml.SelectNodes('/t:Task/t:Triggers/*', $namespace).Count -ne 1 -or
        $xml.SelectNodes('/t:Task/t:Principals/*', $namespace).Count -ne 1 -or
        $xml.SelectNodes('//t:RestartOnFailure', $namespace).Count -ne 0) {
        throw 'UNEXPECTED_TEMPLATE_STRUCTURE'
    }

    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    $arguments = @(
        '-NoLogo'
        '-NoProfile'
        '-NonInteractive'
        '-File'
        (ConvertTo-QuotedArgument -Value $runner)
        '-ConfigPath'
        (ConvertTo-QuotedArgument -Value $ConfigPath)
        '-ResultDirectory'
        (ConvertTo-QuotedArgument -Value $ResultDirectory)
    ) -join ' '

    $values = [ordered]@{
        '/t:Task/t:Principals/t:Principal/t:UserId' = $sid
        '/t:Task/t:Principals/t:Principal/t:LogonType' = 'InteractiveToken'
        '/t:Task/t:Principals/t:Principal/t:RunLevel' = 'LeastPrivilege'
        '/t:Task/t:Triggers/t:CalendarTrigger/t:StartBoundary' = (
            $start.ToString('o')
        )
        '/t:Task/t:Triggers/t:CalendarTrigger/t:Enabled' = 'true'
        '/t:Task/t:Triggers/t:CalendarTrigger/t:ScheduleByDay/t:DaysInterval' = '1'
        '/t:Task/t:Actions/t:Exec/t:Command' = $pwsh
        '/t:Task/t:Actions/t:Exec/t:Arguments' = $arguments
        '/t:Task/t:Actions/t:Exec/t:WorkingDirectory' = $workingDirectory
        '/t:Task/t:Settings/t:MultipleInstancesPolicy' = 'IgnoreNew'
        '/t:Task/t:Settings/t:DisallowStartIfOnBatteries' = 'false'
        '/t:Task/t:Settings/t:StopIfGoingOnBatteries' = 'false'
        '/t:Task/t:Settings/t:AllowHardTerminate' = 'true'
        '/t:Task/t:Settings/t:StartWhenAvailable' = 'false'
        '/t:Task/t:Settings/t:RunOnlyIfNetworkAvailable' = 'false'
        '/t:Task/t:Settings/t:AllowStartOnDemand' = 'false'
        '/t:Task/t:Settings/t:Enabled' = 'true'
        '/t:Task/t:Settings/t:Hidden' = 'false'
        '/t:Task/t:Settings/t:WakeToRun' = 'false'
        '/t:Task/t:Settings/t:ExecutionTimeLimit' = 'PT10M'
        '/t:Task/t:Settings/t:Priority' = '7'
    }

    foreach ($entry in $values.GetEnumerator()) {
        Set-TaskNode -Document $xml -Namespace $namespace `
            -XPath $entry.Key -Value $entry.Value
    }

    if ($xml.OuterXml.Contains('@@')) {
        throw 'UNRESOLVED_TEMPLATE_MARKER'
    }

    # Guardar primero el XML operativo, siempre privado y sin sobrescritura.
    $stream = [IO.FileStream]::new(
        $XmlPath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )

    try {
        $writerSettings = [Xml.XmlWriterSettings]::new()
        $writerSettings.Encoding = [Text.UTF8Encoding]::new($false)
        $writerSettings.Indent = $true
        $writerSettings.CloseOutput = $false

        $writer = [Xml.XmlWriter]::Create($stream, $writerSettings)
        try {
            $xml.Save($writer)
            $writer.Flush()
            $stream.Flush($true)
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    if ($ExportOnly) {
        Write-Output 'XML privado generado; no se registró ninguna tarea.'
        exit 0
    }

    if ($start -le [DateTimeOffset]::UtcNow.AddSeconds(15)) {
        throw 'REGISTRATION_WINDOW_TOO_SHORT'
    }

    # API oficial. TASK_CREATE=2 impide actualizar o reemplazar una tarea
    # existente, incluso si aparece entre la validación y el registro.
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $root = $service.GetFolder('\')

    $registered = $root.RegisterTask(
        $TaskName,
        $xml.OuterXml,
        2,
        $sid,
        $null,
        3,
        $null
    )

    if ($null -eq $registered) {
        throw 'TASK_REGISTRATION_FAILED'
    }

    Write-Output ('Tarea diaria registrada: ' + $TaskName)
    Write-Output (
        'Primer disparo previsto: ' +
        $start.ToString('o') +
        '. Requiere sesión iniciada y ventana privada vigente.'
    )
    exit 0
}
catch {
    [Console]::Error.WriteLine(
        'No se completó la operación. No se reemplazó deliberadamente ' +
        'ninguna tarea. Si hubo registro, verificar su estado antes de repetir.'
    )
    exit 1
}
```

## `tarea_diaria.template.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<Task version="1.4"
      xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Propuesta de respaldo diario FoodStore TPI. Requiere ventana privada confirmada por el operador en cada ejecucion. No acredita un servicio permanente.</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <!-- Horario operativo propuesto: 02:00 UTC-03.
           El creador inserta un DateTimeOffset ISO8601 futuro.
           Para ensayo se utiliza aproximadamente ahora + 90 segundos. -->
      <StartBoundary>@@START_BOUNDARY_ISO8601@@</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="CurrentUser">
      <UserId>@@CURRENT_USER_SID@@</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>false</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="CurrentUser">
    <Exec>
      <Command>@@PWSH_EXE@@</Command>
      <Arguments>-NoLogo -NoProfile -NonInteractive -File "@@RUNNER_PATH@@" -ConfigPath "@@CONFIG_PATH@@" -ResultDirectory "@@PRIVATE_RESULT_DIRECTORY@@"</Arguments>
      <WorkingDirectory>@@SCRIPT_DIRECTORY@@</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
```

## `README.md`

```markdown
# Respaldo Diario FoodStore TPI

## Estado Y Alcance

Estos cuatro archivos son propuestas de código para revisión previa. No se ejecutaron comandos, no se consultó PostgreSQL y no se registraron tareas para producir esta entrega. No existen resultados de ensayo acreditados por estos archivos.

El complemento busca completar el objetivo 7 mediante una configuración diaria entregable y un ensayo posterior, real y coordinado, del Programador de tareas de Windows.

U6 anterior solamente proponía horarios. Este complemento no modifica esa historia, sus evidencias ni sus fuentes. Reutiliza backup_foodstore.ps1, validaciones.sql y tools/ps_common.ps1 sin reescribirlos.

La revisión automatizada de Codex u otra herramienta no constituye firma ni revisión humana del equipo.

## Requisitos

- Windows con Programador de tareas disponible.
- PowerShell Core 7.5 o posterior. El entorno informado dispone de 7.6.5.
- Clientes PostgreSQL 17: psql.exe, pg_dump.exe y pg_restore.exe. El entorno informado dispone de PostgreSQL 17.11.
- Dependencias U6 existentes y revisadas por el operador.
- Usuario actual con sesión iniciada y permisos ordinarios suficientes.
- PostgreSQL ya disponible por coordinación externa. Ningún archivo inicia el servidor.
- Acceso autorizado a foodstore por 127.0.0.1, con DbUser exactamente u5_bootstrap y un puerto entre 1 y 65535.
- Directorios existentes: no se crean automáticamente directorios ni se corrigen ACL.
- Directorio de backups, resultados, configuración y archivo de contraseñas fuera del paquete y fuera de Git.
- Scripts y clientes instalados en ubicaciones de confianza, no modificables por terceros no autorizados.

Las rutas admitidas son rutas locales absolutas con unidad, por ejemplo C:\Lab Privado\resultados. Se admiten espacios. Se rechazan rutas UNC, rutas de dispositivo, comillas dobles, caracteres de control y flujos alternativos NTFS.

No se usan descargas, perfiles de PowerShell, ExecutionPolicy Bypass, servicios nuevos, permisos SQL nuevos ni elevación automática.

## Contrato Privado

ConfigPath debe ser un archivo JSON externo a Git, con exactamente estas ocho claves, respetando mayúsculas y minúsculas:

- U6Root: ruta absoluta al directorio de las dependencias originales.
- PgBin: ruta absoluta al directorio de clientes PostgreSQL 17.
- DbUser: cadena literal u5_bootstrap.
- HostName: cadena literal 127.0.0.1.
- Port: número entero JSON entre 1 y 65535.
- PassFile: ruta absoluta a un archivo de contraseñas existente.
- BackupWorkDir: directorio privado existente para los archivos producidos por U6.
- WindowExpiresUtc: instante UTC ISO8601, terminado en Z o +00:00.

El JSON se interpreta mediante ConvertFrom-Json -DateKind String. No se imprime su contenido. PassFile contiene solamente una ruta: nunca se incorpora la contraseña al JSON ni a los argumentos de procesos.

El operador debe generar WindowExpiresUtc únicamente después de coordinar una ventana sin escritores. Su valor debe ser posterior al momento de validación y no superar los siguientes 60 minutos.

Un ejemplo de expresión para calcular el vencimiento, que no escribe ni confirma por sí misma la ventana, es: `[DateTimeOffset]::UtcNow.AddMinutes(15).ToString('o')`.

No reutilizar una confirmación vieja. Una programación diaria no renueva esta autorización.

## ACL Y Rutas

Antes de leer la configuración, utilizar PassFile, ejecutar el backup o escribir resultados, el runner valida los destinos correspondientes.

ConfigPath, PassFile, BackupWorkDir y el directorio de resultados deben tener DACL protegida, sin herencia habilitada. Los únicos SID admitidos en reglas de permiso son:

- El SID del usuario Windows actual.
- SYSTEM: S-1-5-18.
- Administradores: S-1-5-32-544.
- OWNER RIGHTS: S-1-3-4, solamente si el propietario resuelve al usuario actual.

El propietario debe ser el usuario actual, SYSTEM o Administradores. Las entradas que concedan acceso a otras identidades se rechazan, aunque otra regla pudiera denegarlo. Las reglas de denegación no conceden permisos.

Los archivos de manifiesto y dump pueden heredar permisos desde la carpeta privada, pero tampoco pueden conceder acceso a otras identidades.

Se recorren los ancestros para rechazar reparse points, directorios llamados .git y directorios que contengan un marcador .git, incluido el archivo usado por Git worktrees.

El código no modifica ACL ajenas. El operador debe preparar y revisar las ubicaciones privadas antes del ensayo.

Estos controles no aíslan de un administrador del equipo ni eliminan todas las carreras de sustitución de rutas. No admitir modificaciones concurrentes de configuración, permisos, scripts, dependencias ni directorios durante el trabajo.

## Interfaz De U6 A Revisar

No se suministraron fuentes internas. Por eso no se afirma que se haya comprobado la interfaz real de U6.

Antes del único ensayo, el operador debe revisar que backup_foodstore.ps1 acepte:

`-HostName -Port -DbUser -PgBin -WorkDir -ConfirmNoWrites`

También debe revisar que U6 realice solamente el backup y las lecturas o metadatos locales autorizados: ninguna restauración, DROP, modificación de foodstore, cambio de roles o cambio de ACL.

El runner ejecuta U6 en un proceso hijo mediante:

`pwsh -NoLogo -NoProfile -NonInteractive -File backup_foodstore.ps1`

Nunca se ejecuta U6 con dot-sourcing ni dentro del proceso del runner, porque puede utilizar exit.

### Manifiesto Esperado

La especificación exige comprobar un manifiesto, pero no define su formato interno. Esta propuesta adopta el siguiente contrato explícito y falla de forma cerrada si U6 no lo cumple. No representa un formato observado ni una afirmación sobre las fuentes ausentes.

U6 debe crear un archivo JSON nuevo debajo de BackupWorkDir que contenga:

- status: cadena literal SUCCESS.
- startedUtc: instante UTC ISO8601 con Z o +00:00.
- sourceDatabase: cadena literal foodstore.
- backupFile: ruta absoluta al dump dentro de BackupWorkDir, o ruta relativa a BackupWorkDir.
- backupBytes: entero JSON positivo.
- backupSha256: cadena hexadecimal SHA256 de 64 caracteres.
- baseline: objeto con exactamente counts, invalid y fingerprints.
- baseline.counts: objeto de etiquetas técnicas y enteros no negativos.
- baseline.invalid: objeto de etiquetas técnicas y enteros no negativos.
- baseline.fingerprints: objeto de etiquetas técnicas y cadenas SHA256 hexadecimales de 64 caracteres.

Las etiquetas técnicas admiten letras ASCII, números, punto y guion bajo; deben comenzar por letra o guion bajo y tener como máximo 128 caracteres. No deben contener identidades del negocio, muestras de registros ni valores personales.

Puede haber otros campos en la raíz del manifiesto, pero el runner no los incorpora al resumen.

Antes del ensayo se debe cotejar este contrato con el manifiesto real de U6. Si difiere, revisar únicamente la lectura y validación del manifiesto en el runner con información verificada. No modificar U6, inventar un manifiesto compatible ni omitir sus comprobaciones.

La ausencia de las fuentes impide garantizar aquí la compatibilidad de ese formato. Esta comprobación es un requisito pendiente de revisión, no una ejecución pendiente que deba iniciarse automáticamente.

## Ejecución Del Runner

Validación local sin conexión SQL, backup ni resultado:

`& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'C:\Complemento\run_backup_job.ps1' -ConfigPath 'C:\Lab Privado\config.json' -ResultDirectory 'C:\Lab Privado\resultados' -ValidateOnly`

Esta validación sí ejecuta los clientes PostgreSQL con --version, pero no los conecta a una base.

Ejemplo de ejecución manual, solamente después de coordinación explícita y no como evidencia de disparo horario:

`& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'C:\Complemento\run_backup_job.ps1' -ConfigPath 'C:\Lab Privado\config.json' -ResultPath 'C:\Lab Privado\resultados\resultado-unico.json'`

ResultPath debe ser nuevo. Una colisión no se sobrescribe.

Para la tarea diaria se utiliza ResultDirectory. Cada invocación genera un nombre nuevo con instante UTC y GUID. Esto evita que el segundo día intente sobrescribir el resultado del primero.

El runner valida WindowExpiresUtc y ejecuta una consulta a pg_stat_activity mediante psql -X -w. Rechaza cualquier otra sesión cliente conectada a foodstore.

Esta consulta es una precondición observada: no bloquea conexiones nuevas y no demuestra que el negocio haya sido bloqueado. El operador mantiene la ventana sin escritores hasta finalizar el trabajo.

Antes de iniciar U6 se vuelve a comprobar el vencimiento y la privacidad de los destinos.

Los procesos nativos reciben PGPASSFILE y PGCONNECT_TIMEOUT=10. Se eliminan las variables heredadas cuyo nombre comienza por PG y se establece explícitamente el endpoint autorizado. Esto elimina, entre otras, PGHOSTADDR, PGSERVICE, PGSERVICEFILE, PGOPTIONS y PGPASSWORD heredadas.

No se lee ni imprime la contraseña. La salida y los diagnósticos nativos se capturan en memoria y no se publican ni se guardan en el paquete.

Después de la salida cero de U6 se exige exactamente un manifiesto SUCCESS nuevo, no presente antes de invocar U6, con inicio igual o posterior al comienzo del job y no posterior a la validación.

Se comprueban ubicación privada, existencia, tamaño y SHA256 del dump. El resumen incluye exclusivamente estado, tiempos UTC, base origen, nombre base del archivo, tamaño, SHA256, baseline validada y código nativo.

Un hash no anonimiza el dump, el nombre de archivo ni el contenido de los metadatos. Dumps, manifiestos y resúmenes permanecen privados.

Un fallo devuelve 1. No se fabrica SUCCESS. Cuando el destino ya fue validado y es posible escribirlo, se crea un resumen FAILED con un código de fase genérico. Si no es seguro escribir, no se crea resultado.

Los resultados se escriben mediante FileMode.CreateNew. Un fallo o escritura parcial del resultado también devuelve 1. No se reintenta ni sobrescribe ese archivo.

## XML Y Registro

Los cuatro archivos deben conservarse juntos. La plantilla contiene marcadores deliberadamente no importables y ninguna identidad personal.

crear_tarea_diaria.ps1 carga la plantilla sin permitir DTD, inserta valores mediante el DOM XML y construye argumentos de rutas entrecomillados. No usa Invoke-Expression ni concatena órdenes ejecutables arbitrarias.

El XML operativo contiene SID y rutas locales: es privado. XmlPath debe ser un archivo nuevo dentro de una carpeta privada existente.

Ejemplo de exportación sin registrar tarea:

`& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'C:\Complemento\crear_tarea_diaria.ps1' -ConfigPath 'C:\Lab Privado\config.json' -ResultDirectory 'C:\Lab Privado\resultados' -XmlPath 'C:\Lab Privado\evidencia\propuesta.xml' -ExportOnly`

La validación exige una confirmación vigente incluso para ExportOnly. Esta operación no conecta a PostgreSQL, no ejecuta U6 y no registra tareas.

Si se omite FirstRun, se elige el próximo horario futuro elegible de las 02:00 con desplazamiento UTC-03. La frecuencia es diaria, DaysInterval=1.

Una confirmación creada hoy puede expirar antes de ese horario. El registro no la prolonga: el operador debe renovar la configuración dentro de una ventana realmente coordinada antes de cada ejecución. De lo contrario, el runner falla de forma segura.

La tarea utiliza exclusivamente:

- SID del usuario Windows actual.
- InteractiveToken: necesita sesión iniciada.
- LeastPrivilege: sin solicitar privilegios elevados.
- Una acción pwsh con -NoLogo -NoProfile -NonInteractive.
- IgnoreNew para instancias superpuestas de esta misma tarea.
- Límite de ejecución de diez minutos.
- Sin reintentos automáticos.
- Sin despertar el equipo.
- Ejecución permitida con batería.
- Sin recuperación automática de horarios perdidos.
- Sin inicio manual habilitado en la configuración.
- Sin contraseña ni credenciales almacenadas.

El registro usa la API oficial del Programador con TASK_CREATE, nunca TASK_UPDATE ni TASK_CREATE_OR_UPDATE. No reemplaza una tarea preexistente.

El único formato de nombre aceptado es FoodStore-TPI-Lab-[GUIDhex32]. Si se omite TaskName, se genera un GUID nuevo.

IgnoreNew solamente controla instancias de esa tarea. No es un bloqueo global contra otros trabajos, usuarios o clientes SQL.

## Ensayo Coordinado

El ensayo requiere autorización explícita del operador. No ejecutar estos pasos solamente porque los archivos hayan sido generados.

1. El responsable del laboratorio coordina una ventana sin escritores y confirma que PostgreSQL ya está disponible.
2. El operador revisa las fuentes U6 originales, los cuatro archivos, el contrato del manifiesto y las ACL.
3. El operador crea o renueva el JSON privado con vencimiento futuro de hasta 60 minutos.
4. Se conserva abierta la sesión del usuario que registrará la tarea.
5. Se genera un nombre exclusivo: `$nombre = 'FoodStore-TPI-Lab-' + [guid]::NewGuid().ToString('N')`.
6. Se calcula el primer disparo: `$inicio = [DateTimeOffset]::UtcNow.AddSeconds(90).ToString('o')`.
7. Se registra únicamente la tarea temporal mediante el comando siguiente.
8. Se espera el disparo horario real. No utilizar Start-ScheduledTask ni una ejecución manual del runner para simularlo.
9. Se verifica que la tarea haya terminado, que LastRunTime corresponda al ensayo y que exista el resumen privado esperado.
10. Se exporta evidencia y se deshabilita o retira exclusivamente la tarea temporal identificada por $nombre.
11. Se revisa y sanea el material antes de incorporarlo al entregable.

Comando de registro para el paso 7:

`& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'C:\Complemento\crear_tarea_diaria.ps1' -ConfigPath 'C:\Lab Privado\config.json' -ResultDirectory 'C:\Lab Privado\resultados' -XmlPath 'C:\Lab Privado\evidencia\registro-original.xml' -TaskName $nombre -FirstRun $inicio`

Calcular $inicio inmediatamente antes de ejecutar el comando. Si las validaciones consumen el margen disponible, el registro falla o debe posponerse con una nueva revisión; no forzar un disparo manual.

Una tarea detenida por el límite del Programador puede no alcanzar a escribir su resumen. La ausencia de resumen es un fallo o resultado no acreditado, nunca un éxito implícito.

## Evidencia Privada

Utilizar nombres de archivo nuevos y una carpeta previamente validada como privada. No guardar estas evidencias directamente en Git.

Obtener exclusivamente la tarea del ensayo:

`$tarea = Get-ScheduledTask -TaskPath '\' -TaskName $nombre -ErrorAction Stop`

Obtener su información:

`$info = Get-ScheduledTaskInfo -TaskPath '\' -TaskName $nombre -ErrorAction Stop`

Comprobar que no siga en ejecución antes de finalizar el ensayo:

`$tarea.State`

Registrar privadamente acción, principal, trigger y datos del Programador:

`$evidencia = [ordered]@{ TaskName = $nombre; Action = @($tarea.Actions | Select-Object Execute, Arguments, WorkingDirectory); Principal = ($tarea.Principal | Select-Object UserId, LogonType, RunLevel); Trigger = @($tarea.Triggers | Select-Object StartBoundary, Enabled, DaysInterval); LastRunTime = $info.LastRunTime; LastTaskResult = $info.LastTaskResult; CapturedUtc = [DateTimeOffset]::UtcNow.ToString('o') }`

Convertir sin imprimir:

`$evidenciaJson = ConvertTo-Json -InputObject $evidencia -Depth 12`

Guardar mediante creación exclusiva:

`$archivoEvidencia = [IO.FileStream]::new('C:\Lab Privado\evidencia\scheduler-original.json', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)`

Escribir y cerrar incluso ante un error:

`try { $bytesEvidencia = [Text.UTF8Encoding]::new($false).GetBytes($evidenciaJson); $archivoEvidencia.Write($bytesEvidencia, 0, $bytesEvidencia.Length); $archivoEvidencia.Flush($true) } finally { $archivoEvidencia.Dispose() }`

Exportar el XML realmente registrado, no solamente el XML propuesto:

`$xmlOriginal = Export-ScheduledTask -TaskPath '\' -TaskName $nombre -ErrorAction Stop`

Crear su archivo privado sin sobrescritura:

`$archivoXml = [IO.FileStream]::new('C:\Lab Privado\evidencia\scheduler-original.xml', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)`

Escribir y cerrar:

`try { $bytesXml = [Text.UTF8Encoding]::new($false).GetBytes($xmlOriginal); $archivoXml.Write($bytesXml, 0, $bytesXml.Length); $archivoXml.Flush($true) } finally { $archivoXml.Dispose() }`

Calcular el hash del original privado:

`$hashOriginal = (Get-FileHash -LiteralPath 'C:\Lab Privado\evidencia\scheduler-original.xml' -Algorithm SHA256).Hash.ToLowerInvariant()`

Conservar el valor de $hashOriginal como referencia del original, sin publicar su ruta privada.

Examinar el resumen JSON correspondiente al ensayo dentro del entorno privado. Correlacionar startedUtc y finishedUtc con el disparo observado. No atribuir al ensayo un resumen previo o ajeno.

LastTaskResult=0 por sí solo no reemplaza la comprobación del resumen SUCCESS y del manifiesto. A su vez, un resumen no demuestra por sí solo que el inicio haya sido horario: se requieren los datos del Programador.

No se proporcionan aquí valores de LastRunTime, LastTaskResult, hash, tamaño, duración ni baseline porque todavía no se ejecutó el ensayo.

## Saneamiento

El XML operativo y el exportado contienen datos locales. No incluirlos sin sanear en la entrega.

Sobre una copia en memoria del XML realmente exportado, utilizar un DOM XML y reemplazar:

- UserId por @@CURRENT_USER_SID@@.
- Command por @@PWSH_EXE@@.
- Arguments por la acción con los marcadores de la plantilla.
- WorkingDirectory por @@SCRIPT_DIRECTORY@@.
- Cualquier Author, URI, SecurityDescriptor u otro campo con identidades o rutas locales por un marcador, o eliminarlo si es metadato no necesario para la evidencia.

Mantener los valores observados de LogonType, RunLevel, StartBoundary, DaysInterval y Settings. No convertir valores observados incorrectos en valores esperados.

Ejemplo de inicio de la copia DOM, sin imprimir el XML: `[xml]$xmlSaneado = $xmlOriginal`.

La plantilla entregada sirve de referencia para los marcadores, no sustituye al XML observado. El XML saneado es evidencia para revisión y puede dejar de ser importable.

Guardar el XML saneado en un archivo nuevo. Acompañarlo con el SHA256 del original privado y una nota que explique qué campos fueron sustituidos.

Sanear también el JSON de evidencia: sustituir SID y rutas de Action y Principal; conservar LogonType, RunLevel, trigger, LastRunTime y LastTaskResult observados. No publicar identidades del negocio ni diagnósticos nativos.

Revisar manualmente todos los archivos antes de incorporarlos al paquete. No asumir que un hash, una extensión JSON o los marcadores garantizan anonimato.

## Retiro Del Ensayo

Una vez exportada la evidencia y comprobado que no hay una ejecución en curso, deshabilitar exclusivamente la tarea temporal:

`Disable-ScheduledTask -TaskPath '\' -TaskName $nombre -ErrorAction Stop | Out-Null`

Si corresponde retirarla, utilizar exclusivamente su nombre exacto:

`Unregister-ScheduledTask -TaskPath '\' -TaskName $nombre -Confirm -ErrorAction Stop`

No usar comodines, no retirar otras tareas y no borrar backups ni evidencias privadas como parte de estos comandos.

Verificar después el estado deshabilitado o la ausencia de esa tarea, según la acción elegida. Registrar esa comprobación sin inventar un resultado.

Si hay un error durante la creación o la exportación, comprobar el estado de la tarea exacta antes de repetir. El XML privado puede existir aunque el registro haya fallado.

## Responsables Y Límites

- Responsable del laboratorio: autoriza horario, disponibilidad del equipo y ausencia de escritores.
- Operador: prepara ACL y configuración privada, revisa dependencias, registra la tarea, observa el disparo y la deshabilita o retira.
- Revisor del equipo: contrasta código, manifiesto real, evidencia y saneamiento.
- Responsable de operación futura: define retención, monitorización, renovación diaria de la ventana y respuesta ante fallos antes de considerar un servicio permanente.

Una tarea diaria registrada, ensayada y retirada no equivale a un servicio productivo permanente activo.

Este diseño no mantiene sesiones bloqueadas, no detiene el negocio, no garantiza equipo encendido o sesión iniciada, no renueva confirmaciones y no acredita recuperabilidad mediante una restauración nueva.

La única operación de base autorizada para U6 en este complemento es el backup, además de las lecturas necesarias. Se mantienen origen, roles y ACL SQL. No se inicia PostgreSQL, no se ejecutan restauraciones ni DROP y no se modifica foodstore.
```
