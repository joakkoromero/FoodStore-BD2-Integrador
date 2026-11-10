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
$script:TrustedAncestorSids = @()
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
            # Read/traverse/create-new-child permissions do not by themselves
            # replace an existing protected path. Reject effective permissions
            # that can alter/delete the ancestor or replace an existing child.
            $ancestorAcl = Get-Acl -LiteralPath $item.FullName -ErrorAction Stop
            $ancestorOwner = $ancestorAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value
            if ($ancestorOwner -notin $script:TrustedAncestorSids) {
                throw 'UNTRUSTED_ANCESTOR_OWNER'
            }
            $dangerousRights = [Security.AccessControl.FileSystemRights]::Delete -bor
                [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
                [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
                [Security.AccessControl.FileSystemRights]::TakeOwnership -bor
                [Security.AccessControl.FileSystemRights]::WriteData
            foreach ($ancestorRule in $ancestorAcl.GetAccessRules(
                $true, $true, [Security.Principal.SecurityIdentifier])) {
                if ($ancestorRule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
                    ($ancestorRule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)) {
                    continue
                }
                $ancestorSid = $ancestorRule.IdentityReference.Value
                $trustedOwnerRights = ($ancestorSid -eq 'S-1-3-4' -and
                    $ancestorOwner -in $script:TrustedAncestorSids)
                if ($ancestorSid -notin $script:TrustedAncestorSids -and -not $trustedOwnerRights -and
                    ($ancestorRule.FileSystemRights -band $dangerousRights) -ne 0) {
                    throw 'ANCESTOR_MUTABLE_BY_OTHER_IDENTITY'
                }
            }
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
        [bool] $RequireProtected = $false
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
    $tables = @('categoria', 'producto', 'usuario', 'pedido', 'detalle_pedido')
    $expected = @{ counts = $tables; fingerprints = $tables; invalid = @('productos', 'detalles') }
    if ($Baseline.Count -ne 3) { throw 'UNSUPPORTED_BASELINE_SCHEMA' }
    $safe = [ordered]@{}
    foreach ($section in @('counts', 'invalid', 'fingerprints')) {
        if (-not $Baseline.Contains($section) -or $Baseline[$section] -isnot [Collections.IDictionary] -or
            $Baseline[$section].Count -ne $expected[$section].Count) { throw 'UNSUPPORTED_BASELINE_SCHEMA' }
        $values = [ordered]@{}
        foreach ($key in $expected[$section]) {
            if (-not $Baseline[$section].Contains($key)) { throw 'INVALID_BASELINE_LABEL' }
            $value = $Baseline[$section][$key]
            if ($section -eq 'fingerprints') {
                if ($value -isnot [string] -or $value -cnotmatch '^[0-9a-f]{32}$') { throw 'INVALID_FINGERPRINT' }
                $values[$key] = $value
            } else {
                if (($value -isnot [long] -and $value -isnot [int]) -or $value -lt 0 -or
                    ($section -eq 'invalid' -and $value -ne 0)) { throw 'INVALID_BASELINE_COUNT' }
                $values[$key] = [long]$value
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
    # The Windows volume root can be owned by its maintenance service.
    # This exception is only for ancestors, never private files/directories.
    $trustedInstallerSid = [Security.Principal.NTAccount]::new(
        'NT SERVICE\TrustedInstaller').Translate([Security.Principal.SecurityIdentifier]).Value
    $script:TrustedAncestorSids = @($script:AllowedSids) + @($trustedInstallerSid)

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

    # Validate each internal destination BEFORE U6 can write a log or a dump.
    # The operator prepares these empty directories with private ACLs.
    $privateBackups = Join-Path $config['BackupWorkDir'] 'backups'
    $privateLogs = Join-Path $config['BackupWorkDir'] 'logs'
    foreach ($internalDirectory in @($privateBackups, $privateLogs)) {
        Assert-PrivateItem -Path $internalDirectory -Directory $true
    }

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

    foreach ($file in Get-ChildItem -LiteralPath $privateLogs `
            -Filter '*.manifest.json' -File -Force) {
        [void]$previousJson.Add($file.FullName)
    }

    # Revalidación inmediatamente antes de pasar -ConfirmNoWrites.
    # La consulta anterior es una observación, no un cerrojo.
    Assert-LiveWindow -Expires $expires
    Assert-PrivateItem -Path $ConfigPath -Directory $false
    Assert-PrivateItem -Path $config['PassFile'] -Directory $false
    Assert-PrivateItem -Path $config['BackupWorkDir'] -Directory $true

    foreach ($internalDirectory in @($privateBackups, $privateLogs)) {
        Assert-PrivateItem -Path $internalDirectory -Directory $true
    }

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

    foreach ($file in Get-ChildItem -LiteralPath $privateLogs `
            -Filter '*.manifest.json' -File -Force) {
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

        if (-not $manifest.Contains('startUtc') -or
            $manifest['startUtc'] -isnot [string]) {
            throw 'SUCCESS_WITHOUT_VALID_START'
        }

        $manifestStart = Read-UtcInstant -Value $manifest['startUtc']
        if (-not $manifest.Contains('endUtc')) { throw 'SUCCESS_WITHOUT_VALID_END' }
        $manifestEnd = Read-UtcInstant -Value $manifest['endUtc']
        if ($manifestEnd -lt $manifestStart -or $manifestEnd -gt [DateTimeOffset]::UtcNow) { throw 'INVALID_MANIFEST_END' }
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
        'database', 'file', 'size',
        'sha256', 'baseline'
    )) {
        if (-not $manifest.Contains($field)) {
            throw 'UNSUPPORTED_MANIFEST_SCHEMA'
        }
    }

    if ($manifest['database'] -cne 'foodstore' -or
        $manifest['file'] -isnot [string] -or
        $manifest['sha256'] -isnot [string] -or
        $manifest['sha256'] -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'INVALID_MANIFEST_METADATA'
    }

    if (($manifest['size'] -isnot [long] -and
         $manifest['size'] -isnot [int]) -or
        $manifest['size'] -le 0) {
        throw 'INVALID_BACKUP_SIZE'
    }

    $declaredBackup = $manifest['file']
    if ($declaredBackup -cnotmatch '^foodstore_[0-9]{8}T[0-9]{13}Z_[0-9a-f]{32}\.dump$') {
        throw 'INVALID_BACKUP_BASENAME'
    }
    $backupPath = Get-NormalizedLocalPath -Path (
        Join-Path (Join-Path $config['BackupWorkDir'] 'backups') $declaredBackup
    )

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
        if ($backupBytes -ne [long]$manifest['size']) {
            throw 'BACKUP_SIZE_MISMATCH'
        }

        $hashBytes = [Security.Cryptography.SHA256]::HashData($backupStream)
        $backupSha256 = [Convert]::ToHexString($hashBytes).ToLowerInvariant()

        if ($backupSha256 -cne $manifest['sha256'].ToLowerInvariant()) {
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
