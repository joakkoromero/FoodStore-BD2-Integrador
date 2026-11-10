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

    # RegisterTask consumes a Unicode BSTR, not the UTF-8 file byte stream.
    # Omit the declaration only from this in-memory clone; keep the file valid UTF-8.
    $comXml = $xml.CloneNode($true)
    if ($comXml.FirstChild -is [Xml.XmlDeclaration]) { [void]$comXml.RemoveChild($comXml.FirstChild) }
    $registered = $root.RegisterTask(
        $TaskName,
        $comXml.OuterXml,
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
