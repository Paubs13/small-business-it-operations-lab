#Requires -Version 5.1
<#
.SYNOPSIS
    Finds Critical and Error events in Windows Event Logs within a configurable time range.

.PARAMETER LogName
    One or more event log names (wildcards allowed). Default: System, Application.

.PARAMETER HoursBack
    Look back this many hours from now (1-8760). Default: 24. Used when -StartTime is not given.

.PARAMETER StartTime
    Absolute start of the time range. Use together with -EndTime (defaults to now).

.PARAMETER EndTime
    Absolute end of the time range. Default: now.

.PARAMETER Level
    Which severities to include: Critical, Error, or both (default).

.PARAMETER EventId
    Optional filter on specific event IDs.

.PARAMETER ProviderName
    Optional filter on event sources (providers).

.PARAMETER MaxEvents
    Maximum number of events returned overall, newest first. Default: 500.

.PARAMETER ComputerName
    Query a remote computer instead of the local one (needs remote event log access).

.PARAMETER Credential
    Credential for the remote computer. Only valid together with -ComputerName.

.PARAMETER MessageMaxLength
    Truncate messages to this many characters. 0 (default) keeps the full message.

.PARAMETER ExportPath
    Optional .csv or .json file to write the results to.

.PARAMETER Force
    Overwrite an existing export file without asking.

.EXAMPLE
    .\Get-CriticalErrorEvents.ps1
    Critical and Error events from System and Application in the last 24 hours.

.EXAMPLE
    .\Get-CriticalErrorEvents.ps1 -HoursBack 72 -Level Critical | Format-Table -AutoSize
    Only Critical events from the last 3 days.

.EXAMPLE
    .\Get-CriticalErrorEvents.ps1 -StartTime '2026-11-01' -EndTime '2026-11-10' -ExportPath .\events.csv
    Events in an absolute range, exported to CSV.
#>
[CmdletBinding(DefaultParameterSetName = 'Relative', SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$LogName = @('System', 'Application'),

    [Parameter(ParameterSetName = 'Relative')]
    [ValidateRange(1, 8760)]
    [int]$HoursBack = 24,

    [Parameter(ParameterSetName = 'Absolute', Mandatory = $true)]
    [datetime]$StartTime,

    [Parameter(ParameterSetName = 'Absolute')]
    [datetime]$EndTime = (Get-Date),

    [ValidateSet('Critical', 'Error')]
    [string[]]$Level = @('Critical', 'Error'),

    [ValidateRange(0, 65535)]
    [int[]]$EventId,

    [string[]]$ProviderName,

    [ValidateRange(1, 100000)]
    [int]$MaxEvents = 500,

    [string]$ComputerName,

    [pscredential]$Credential,

    [ValidateRange(0, 32768)]
    [int]$MessageMaxLength = 0,

    [string]$ExportPath,

    [switch]$Force
)

function Test-IsWindowsPlatform {
    # Get-WinEvent only exists on Windows. Windows PowerShell 5.1 is always Windows.
    if ($PSVersionTable.PSEdition -eq 'Core') { return [bool]$IsWindows }
    return $true
}

function Test-IsElevated {
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Resolve-TimeRange {
    [CmdletBinding()]
    param(
        [Nullable[datetime]]$StartTime,
        [datetime]$EndTime,
        [int]$HoursBack
    )

    $now = Get-Date
    if ($null -eq $StartTime) {
        $EndTime   = $now
        $StartTime = $now.AddHours(-$HoursBack)
    }

    if ($StartTime -ge $EndTime) {
        throw "StartTime ($StartTime) must be earlier than EndTime ($EndTime)."
    }
    if ($StartTime -gt $now) {
        throw "StartTime ($StartTime) is in the future; there are no events to find."
    }
    if ($EndTime -gt $now) { $EndTime = $now }   # Clamp: nothing exists beyond 'now'.

    [pscustomobject]@{ StartTime = $StartTime; EndTime = $EndTime }
}

function Resolve-EventLogName {
    <# Expands wildcards and verifies each log exists and is enabled. Returns usable log names. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$LogName,
        [hashtable]$ConnectionParameter = @{}
    )

    $resolved = New-Object System.Collections.Generic.List[string]
    foreach ($name in $LogName) {
        try {
            $logs = @(Get-WinEvent -ListLog $name -ErrorAction Stop @ConnectionParameter)
            foreach ($log in $logs) {
                if (-not $log.IsEnabled) {
                    Write-Warning "Log '$($log.LogName)' is disabled, so it holds no new events. Skipping."
                    continue
                }
                if (-not $resolved.Contains($log.LogName)) { $resolved.Add($log.LogName) }
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-Warning "Access denied while looking up log '$name'. Try a user with event log read rights. Details: $($_.Exception.Message)"
        }
        catch {
            Write-Warning "Log '$name' could not be used: $($_.Exception.Message)"
        }
    }
    $resolved.ToArray()
}

function Get-CriticalErrorEvent {
    <#
    .SYNOPSIS
        Returns Critical/Error events as structured objects. Failures per log are reported
        as warnings and do not stop the other logs from being queried.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$LogName,
        [Parameter(Mandatory = $true)][datetime]$StartTime,
        [Parameter(Mandatory = $true)][datetime]$EndTime,
        [ValidateSet('Critical', 'Error')][string[]]$Level = @('Critical', 'Error'),
        [int[]]$EventId,
        [string[]]$ProviderName,
        [int]$MaxEvents = 500,
        [int]$MessageMaxLength = 0,
        [hashtable]$ConnectionParameter = @{}
    )

    $levelMap = @{ Critical = 1; Error = 2 }
    $levelNames = @{ 1 = 'Critical'; 2 = 'Error' }
    $levelValues = @($Level | Sort-Object -Unique | ForEach-Object { $levelMap[$_] })

    foreach ($log in $LogName) {
        $filter = @{
            LogName   = $log
            Level     = $levelValues
            StartTime = $StartTime
            EndTime   = $EndTime
        }
        if ($EventId)      { $filter['Id'] = $EventId }
        if ($ProviderName) { $filter['ProviderName'] = $ProviderName }

        try {
            $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop @ConnectionParameter
        }
        catch [System.UnauthorizedAccessException] {
            $hint = if ($log -eq 'Security') {
                'The Security log requires an elevated session (Run as administrator) or membership in the Event Log Readers group.'
            } else {
                'Run as a user with read access to this log (e.g. Event Log Readers group).'
            }
            Write-Warning "Access denied reading log '$log'. $hint"
            continue
        }
        catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                Write-Verbose "No matching events in '$log' for the selected range."
            }
            else {
                Write-Warning "Could not read log '$log': $($_.Exception.Message)"
            }
            continue
        }

        foreach ($e in $events) {
            $message = $e.Message
            if ([string]::IsNullOrWhiteSpace($message)) {
                $message = '(message unavailable: the source''s message DLL is missing or not registered)'
            }
            if ($MessageMaxLength -gt 0 -and $message.Length -gt $MessageMaxLength) {
                $message = $message.Substring(0, $MessageMaxLength) + '...'
            }

            $obj = [pscustomobject]@{
                TimeCreated = $e.TimeCreated
                LogName     = $e.LogName
                Level       = $levelNames[[int]$e.Level]
                EventId     = $e.Id
                Source      = $e.ProviderName
                MachineName = $e.MachineName
                Message     = $message
            }
            $obj.PSObject.TypeNames.Insert(0, 'CriticalErrorEvent')
            $obj
        }
    }
}

function Export-EventReport {
    <# Exports events to .csv/.json. Asks before overwriting unless -Force is given. #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$InputObject,
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Force
    )

    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -notin '.csv', '.json') {
        Write-Warning "Export skipped: '$Path' must end in .csv or .json."
        return
    }

    try {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $parent   = Split-Path -Path $fullPath -Parent
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            Write-Warning "Export skipped: folder '$parent' does not exist."
            return
        }

        if ((Test-Path -LiteralPath $fullPath) -and -not $Force) {
            $proceed = $false
            try {
                $proceed = $PSCmdlet.ShouldContinue("'$fullPath' already exists. Overwrite it?", 'Overwrite export file')
            }
            catch {
                Write-Warning "Export skipped: '$fullPath' exists and no interactive confirmation is possible. Use -Force to overwrite."
                return
            }
            if (-not $proceed) {
                Write-Warning 'Export cancelled; existing file left untouched.'
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($fullPath, 'Write event report')) {
            if ($extension -eq '.csv') {
                $InputObject | Export-Csv -LiteralPath $fullPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            }
            else {
                ConvertTo-Json -InputObject @($InputObject) -Depth 3 -ErrorAction Stop |
                    Set-Content -LiteralPath $fullPath -Encoding UTF8 -ErrorAction Stop
            }
            Write-Information "Exported $(@($InputObject).Count) event(s) to $fullPath" -InformationAction Continue
        }
    }
    catch {
        Write-Warning "Export failed for '$Path': $($_.Exception.Message)"
    }
}

# ---- Main (skipped when the script is dot-sourced to reuse the functions) ----
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-IsWindowsPlatform)) {
        Write-Error 'This script reads Windows Event Logs and only runs on Windows.'
        return
    }
    if ($Credential -and -not $ComputerName) {
        Write-Error '-Credential can only be used together with -ComputerName.'
        return
    }

    try {
        $range = Resolve-TimeRange -StartTime $(if ($PSCmdlet.ParameterSetName -eq 'Absolute') { $StartTime } else { $null }) `
                                   -EndTime $EndTime -HoursBack $HoursBack
    }
    catch {
        Write-Error "Invalid time range: $($_.Exception.Message)"
        return
    }

    $connection = @{}
    if ($ComputerName) { $connection['ComputerName'] = $ComputerName }
    if ($Credential)   { $connection['Credential']   = $Credential }

    if (-not $ComputerName -and -not (Test-IsElevated)) {
        Write-Verbose 'Running without elevation. Logs such as Security may be skipped.'
    }

    $logs = @(Resolve-EventLogName -LogName $LogName -ConnectionParameter $connection)
    if ($logs.Count -eq 0) {
        Write-Error 'None of the requested logs could be queried. See the warnings above.'
        return
    }

    $queryArgs = @{
        LogName             = $logs
        StartTime           = $range.StartTime
        EndTime             = $range.EndTime
        Level               = $Level
        MaxEvents           = $MaxEvents
        MessageMaxLength    = $MessageMaxLength
        ConnectionParameter = $connection
    }
    if ($EventId)      { $queryArgs['EventId']      = $EventId }
    if ($ProviderName) { $queryArgs['ProviderName'] = $ProviderName }

    $results = @(Get-CriticalErrorEvent @queryArgs |
        Sort-Object -Property TimeCreated -Descending |
        Select-Object -First $MaxEvents)

    $summary = '{0} event(s) found in [{1}] between {2} and {3}.' -f
        $results.Count, ($logs -join ', '), $range.StartTime, $range.EndTime
    Write-Information $summary -InformationAction Continue

    if ($ExportPath) {
        Export-EventReport -InputObject $results -Path $ExportPath -Force:$Force -WhatIf:$WhatIfPreference
    }

    $results
}