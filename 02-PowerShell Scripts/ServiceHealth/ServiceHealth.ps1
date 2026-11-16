<#
.SYNOPSIS
    Reports service status and startup type, and separates services that should
    be running (Automatic but Stopped) from services that are normally stopped.

.PARAMETER ComputerName
    Computer(s) to query. Defaults to the local computer. Remote queries use
    CIM over WinRM and need administrative rights on the remote machine.

.PARAMETER ServiceName
    One or more wildcard patterns matched against the service name or display
    name (for example 'Win*', '*sql*'). Defaults to '*' (all services).

.PARAMETER ProblemsOnly
    Return only services in the 'AutoButStopped' category.

.PARAMETER ExportCsvPath
    Path of a .csv file to write the returned objects to. The folder must exist.

.PARAMETER StartStoppedAutoServices
    Try to start local services in the 'AutoButStopped' category. Requires an
    elevated session. Trigger-start services are skipped because Windows starts
    them on demand. Prompts before each start; use -WhatIf to preview.

.PARAMETER ShowSummary
    Also print a colored, human-readable summary to the console.

.EXAMPLE
    .\Get-ServiceStartupReport.ps1

.EXAMPLE
    .\Get-ServiceStartupReport.ps1 -ProblemsOnly -ShowSummary

.EXAMPLE
    .\Get-ServiceStartupReport.ps1 -ServiceName '*update*' -ExportCsvPath C:\Temp\services.csv

.EXAMPLE
    .\Get-ServiceStartupReport.ps1 -StartStoppedAutoServices -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [ValidateNotNullOrEmpty()]
    [string[]]$ServiceName = '*',

    [switch]$ProblemsOnly,

    [ValidateScript({
        if ([IO.Path]::GetExtension($_) -ne '.csv') {
            throw "ExportCsvPath must end in .csv (got '$_')."
        }
        $folder = Split-Path -Path $_ -Parent
        if ([string]::IsNullOrEmpty($folder)) { $folder = '.' }
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            throw "The folder '$folder' does not exist."
        }
        $true
    })]
    [string]$ExportCsvPath,

    [switch]$StartStoppedAutoServices,

    [switch]$ShowSummary
)

#region Helper functions

function Test-IsWindowsHost {
    # $IsWindows does not exist in Windows PowerShell 5.1
    ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
}

function Test-IsElevated {
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        $false
    }
}

function Test-IsLocalComputer {
    param([Parameter(Mandatory)][string]$Name)
    $Name -in @('.', 'localhost', $env:COMPUTERNAME, [Environment]::MachineName)
}

function Get-StartupTypeLabel {
    param([string]$StartMode, [bool]$DelayedAutoStart)
    switch ($StartMode) {
        'Auto'  { if ($DelayedAutoStart) { 'Automatic (Delayed)' } else { 'Automatic' } }
        default { $StartMode }   # Manual, Disabled, Boot, System
    }
}

function Get-ServiceCategory {
    <# Pure classification logic: takes raw values, returns Category and Note. #>
    param(
        [string]$StartMode,
        [string]$State,
        [long]$ExitCode,
        [object]$IsTriggerStart    # $true, $false or $null (unknown)
    )

    $isAuto = $StartMode -in 'Auto', 'Boot', 'System'

    if ($State -eq 'Running') {
        $category = 'Running'
        $note = if ($isAuto) { '' } else { 'Running but not configured to start automatically' }
    }
    elseif ($State -eq 'Stopped') {
        if ($isAuto) {
            $category = 'AutoButStopped'
            # 1077 = service never started since boot; 0 = clean exit
            $note = if ($ExitCode -notin 0, 1077) {
                "Last exit code $ExitCode - possible failure"
            }
            elseif ($IsTriggerStart -eq $true) {
                'Trigger-start service; may legitimately be idle'
            }
            else {
                'Configured to run automatically - investigate'
            }
        }
        else {
            $category = 'NormallyStopped'
            $note = if ($StartMode -eq 'Disabled') { 'Disabled' } else { 'Starts on demand' }
        }
    }
    else {
        $category = 'Other'
        $note = "Current state: $State"
    }

    [pscustomobject]@{ Category = $category; Note = $note }
}

function Get-ServiceStartupInfo {
    <# Queries one computer and returns ServiceStartupInfo objects. Never throws. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string[]]$ServiceName
    )

    $isLocal = Test-IsLocalComputer -Name $ComputerName
    $label   = if ($isLocal) { $env:COMPUTERNAME } else { $ComputerName }

    try {
        $cimArgs = @{ ClassName = 'Win32_Service'; ErrorAction = 'Stop' }
        if (-not $isLocal) { $cimArgs['ComputerName'] = $ComputerName }
        Write-Verbose "Querying services on $label"
        $rawServices = @(Get-CimInstance @cimArgs)
    }
    catch {
        $message = $_.Exception.Message
        $hint = switch -Regex ($message) {
            'denied'                 { 'Access was denied. Remote queries usually need administrator rights on the target computer.'; break }
            'WinRM|RPC|unavailable|network path|cannot connect' { 'The computer could not be reached. Check the name, network, firewall and that WinRM is enabled.'; break }
            default                  { 'See the error message for details.' }
        }
        Write-Error "Could not read services from '$label'. $hint ($message)"
        return
    }

    $matchCount = 0
    foreach ($svc in $rawServices) {
        $isMatch = $false
        foreach ($pattern in $ServiceName) {
            if ($svc.Name -like $pattern -or $svc.DisplayName -like $pattern) { $isMatch = $true; break }
        }
        if (-not $isMatch) { continue }
        $matchCount++

        # Trigger info lives in the local registry; unknown ($null) for remote computers.
        $isTrigger = $null
        if ($isLocal) {
            try {
                $isTrigger = Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)\TriggerInfo" -ErrorAction Stop
            }
            catch {
                Write-Verbose "Could not read trigger info for $($svc.Name): $($_.Exception.Message)"
            }
        }

        $class = Get-ServiceCategory -StartMode $svc.StartMode -State $svc.State `
                                     -ExitCode ([long]$svc.ExitCode) -IsTriggerStart $isTrigger

        [pscustomobject]@{
            PSTypeName     = 'ServiceStartupInfo'
            ComputerName   = $label
            Name           = $svc.Name
            DisplayName    = $svc.DisplayName
            Status         = [string]$svc.State
            StartupType    = Get-StartupTypeLabel -StartMode $svc.StartMode -DelayedAutoStart ([bool]$svc.DelayedAutoStart)
            StartMode      = [string]$svc.StartMode
            Category       = $class.Category
            Note           = $class.Note
            ExitCode       = [long]$svc.ExitCode
            IsTriggerStart = $isTrigger
            ActionResult   = $null
        }
    }

    if ($matchCount -eq 0) {
        Write-Warning "No services on '$label' matched: $($ServiceName -join ', ')"
    }
}

function Start-StoppedAutoService {
    <# Starts 'AutoButStopped' services after confirmation. Updates objects in place. #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject]$InputObject
    )

    begin   { $elevated = Test-IsElevated }
    process {
        $item = $InputObject
        if ($item.Category -ne 'AutoButStopped') { return }

        if (-not (Test-IsLocalComputer -Name $item.ComputerName)) {
            $item.ActionResult = 'Skipped: starting services is only supported on the local computer'
            return
        }
        if ($item.IsTriggerStart -eq $true) {
            $item.ActionResult = 'Skipped: trigger-start service, Windows starts it on demand'
            return
        }
        if (-not $elevated) {
            $item.ActionResult = 'Skipped: requires an elevated (Run as administrator) session'
            return
        }

        if ($PSCmdlet.ShouldProcess("$($item.Name) ($($item.DisplayName))", 'Start service')) {
            try {
                Start-Service -Name $item.Name -ErrorAction Stop
                $item.Status = [string](Get-Service -Name $item.Name -ErrorAction Stop).Status
                $class = Get-ServiceCategory -StartMode $item.StartMode -State $item.Status `
                                             -ExitCode $item.ExitCode -IsTriggerStart $item.IsTriggerStart
                $item.Category     = $class.Category
                $item.Note         = $class.Note
                $item.ActionResult = 'Started'
            }
            catch {
                $item.ActionResult = "Failed: $($_.Exception.Message)"
            }
        }
        else {
            $item.ActionResult = 'Skipped: not confirmed (or -WhatIf)'
        }
    }
}

function Write-ServiceSummary {
    <# Human-readable console summary. The structured objects remain the real output. #>
    param([AllowEmptyCollection()][psobject[]]$Report = @())

    Write-Host ''
    Write-Host '--- Summary ---' -ForegroundColor Cyan
    if ($Report.Count -eq 0) {
        Write-Host 'No services to summarize.'
        return
    }

    Write-Host ("Total services : {0}" -f $Report.Count)
    $Report | Group-Object Category | Sort-Object Name | ForEach-Object {
        Write-Host ("{0,-15}: {1}" -f $_.Name, $_.Count)
    }

    $problems = @($Report | Where-Object Category -eq 'AutoButStopped')
    if ($problems.Count -gt 0) {
        Write-Host ''
        Write-Host 'Automatic but stopped:' -ForegroundColor Yellow
        foreach ($p in $problems) {
            Write-Host ("  - [{0}] {1} ({2}) [{3}] {4}" -f $p.ComputerName, $p.DisplayName, $p.Name, $p.StartupType, $p.Note) -ForegroundColor Yellow
        }
    }
    else {
        Write-Host 'No Automatic services are stopped.' -ForegroundColor Green
    }
    Write-Host ''
}

#endregion

#region Main

if (-not (Test-IsWindowsHost)) {
    throw 'This script only works on Windows (it uses the Win32_Service CIM class).'
}

# Default table view; use "Format-Table *" or "Format-List *" for every property.
Update-TypeData -TypeName 'ServiceStartupInfo' -DefaultDisplayPropertySet Name, Status, StartupType, Category -Force

$report = @(foreach ($computer in $ComputerName) {
    Get-ServiceStartupInfo -ComputerName $computer -ServiceName $ServiceName
})

if ($StartStoppedAutoServices) {
    if (-not (Test-IsElevated)) {
        Write-Warning 'Starting services requires an elevated session. Reopen PowerShell with "Run as administrator"; no services will be started.'
    }
    $report | Start-StoppedAutoService
}

$output = if ($ProblemsOnly) { @($report | Where-Object Category -eq 'AutoButStopped') } else { $report }
$output = @($output | Sort-Object @{ Expression = { $_.Category -ne 'AutoButStopped' } }, ComputerName, Category, DisplayName)

if ($ExportCsvPath) {
    try {
        $output | Export-Csv -LiteralPath $ExportCsvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Verbose "Exported $($output.Count) rows to $ExportCsvPath"
    }
    catch {
        Write-Error "Could not write '$ExportCsvPath'. Check that the file is not open elsewhere and that you can write to that folder. ($($_.Exception.Message))"
    }
}

if ($ShowSummary) {
    Write-ServiceSummary -Report $report   # printed before the table
}

$output

#endregion