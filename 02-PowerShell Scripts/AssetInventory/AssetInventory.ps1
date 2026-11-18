#Requires -Version 5.1
<#
.SYNOPSIS
    Collects hardware, OS, disk and installed-software inventory and exports it to CSV.

.PARAMETER ComputerName
    One or more computer names or IPv4 addresses. Defaults to the local computer.

.PARAMETER Credential
    Optional credential for remote computers. Ignored for the local computer.

.PARAMETER OutputDirectory
    Folder for the CSV files. Created if missing. Defaults to .\InventoryOutput.

.PARAMETER SkipSoftware
    Skip the installed-software inventory (faster, and avoids needing WinRM remoting).

.PARAMETER TimeoutSeconds
    Per-operation timeout for remote CIM queries (1-300). Default 30.

.PARAMETER Force
    Overwrite existing output files without prompting.

.PARAMETER PassThru
    Emit full result objects (Summary, LogicalDisks, PhysicalDisks, Software) instead of
    only the summary objects.

.EXAMPLE
    .\Get-SystemInventory.ps1
    Inventory the local computer and write CSVs to .\InventoryOutput.

.EXAMPLE
    .\Get-SystemInventory.ps1 -ComputerName PC01,PC02 -Credential (Get-Credential) -OutputDirectory C:\Reports
    Inventory two remote computers.

.EXAMPLE
    .\Get-SystemInventory.ps1 -SkipSoftware -WhatIf
    Show which files would be written, without writing anything.

.EXAMPLE
    $r = .\Get-SystemInventory.ps1 -PassThru; $r.LogicalDisks | Where-Object PercentFree -lt 15
    Work with the structured objects directly.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -match '^[A-Za-z0-9\.][A-Za-z0-9\.\-_]{0,254}$') { $true }
        else { throw "'$_' is not a valid computer name or IPv4 address." }
    })]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [pscredential]$Credential,

    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path -Path (Get-Location).Path -ChildPath 'InventoryOutput'),

    [switch]$SkipSoftware,

    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 30,

    [switch]$Force,

    [switch]$PassThru
)

Set-StrictMode -Version 2.0

#region Helper functions

function Test-IsElevated {
    <# Returns $true if the current process is running as Administrator. Informational only. #>
    [CmdletBinding()]
    param()
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-IsLocalComputer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)
    $localNames = @('.', 'localhost', '127.0.0.1', $env:COMPUTERNAME, "$($env:COMPUTERNAME).$($env:USERDNSDOMAIN)")
    return ($localNames -contains $ComputerName)
}

function ConvertTo-GB {
    [CmdletBinding()]
    param($Bytes)
    if ($null -eq $Bytes -or $Bytes -eq '') { return $null }
    return [math]::Round(([double]$Bytes / 1GB), 2)
}

function ConvertTo-CleanSerial {
    <# Normalises serial numbers; flags empty values and OEM placeholder strings. #>
    [CmdletBinding()]
    param([AllowNull()][string]$Value)
    $placeholders = @('To Be Filled By O.E.M.', 'Default string', 'System Serial Number',
                      'None', 'Not Specified', 'Not Applicable', 'Unknown', 'N/A')
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'Unavailable' }
    $trimmed = $Value.Trim()
    if (($placeholders -contains $trimmed) -or ($trimmed -match '^(0+|x+|\.+|-+)$')) {
        return 'Unavailable (placeholder)'
    }
    return $trimmed
}

function Invoke-CimQuerySafe {
    <# Runs Get-CimInstance; on failure records a note and returns $null instead of throwing. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Notes,
        [Microsoft.Management.Infrastructure.CimSession]$CimSession,
        [string]$Filter
    )
    try {
        $query = @{ ClassName = $ClassName; ErrorAction = 'Stop' }
        if ($CimSession) { $query['CimSession'] = $CimSession }
        if ($Filter)     { $query['Filter']     = $Filter }
        return @(Get-CimInstance @query)
    }
    catch {
        $reason = $_.Exception.Message.Trim()
        if ($reason -match 'Access is denied|access denied') {
            $reason += ' (insufficient permissions; run as a user with rights on the target)'
        }
        $Notes.Add("$Label unavailable: $reason")
        return $null
    }
}

function New-InventorySession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$Credential,
        [int]$TimeoutSeconds = 30
    )
    $params = @{
        ComputerName        = $ComputerName
        OperationTimeoutSec = $TimeoutSeconds
        ErrorAction         = 'Stop'
    }
    if ($Credential) { $params['Credential'] = $Credential }
    return New-CimSession @params
}

#endregion

#region Collectors

function Get-HardwareInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Notes,
        [Microsoft.Management.Infrastructure.CimSession]$CimSession
    )
    $cs    = Invoke-CimQuerySafe -ClassName Win32_ComputerSystem -Label 'Computer system info' -Notes $Notes -CimSession $CimSession
    $bios  = Invoke-CimQuerySafe -ClassName Win32_BIOS           -Label 'BIOS info'            -Notes $Notes -CimSession $CimSession
    $board = Invoke-CimQuerySafe -ClassName Win32_BaseBoard      -Label 'Baseboard info'       -Notes $Notes -CimSession $CimSession
    $cpu   = Invoke-CimQuerySafe -ClassName Win32_Processor      -Label 'Processor info'       -Notes $Notes -CimSession $CimSession

    $cs0    = if ($cs)    { $cs[0] }    else { $null }
    $bios0  = if ($bios)  { $bios[0] }  else { $null }
    $board0 = if ($board) { $board[0] } else { $null }

    $cores = $null; $logical = $null; $cpuName = $null
    if ($cpu) {
        $cpuName = ($cpu | Select-Object -First 1).Name.Trim()
        $cores   = ($cpu | Measure-Object -Property NumberOfCores -Sum).Sum
        $logical = ($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    }

    [pscustomobject]@{
        Manufacturer      = if ($cs0)    { $cs0.Manufacturer } else { $null }
        Model             = if ($cs0)    { $cs0.Model } else { $null }
        SerialNumber      = ConvertTo-CleanSerial -Value $(if ($bios0)  { $bios0.SerialNumber }  else { $null })
        BaseboardSerial   = ConvertTo-CleanSerial -Value $(if ($board0) { $board0.SerialNumber } else { $null })
        BiosVersion       = if ($bios0)  { $bios0.SMBIOSBIOSVersion } else { $null }
        BiosReleaseDate   = if ($bios0 -and $bios0.ReleaseDate) { $bios0.ReleaseDate.ToString('yyyy-MM-dd') } else { $null }
        Domain            = if ($cs0)    { $cs0.Domain } else { $null }
        ProcessorName     = $cpuName
        ProcessorCores    = $cores
        LogicalProcessors = $logical
        TotalMemoryGB     = if ($cs0)    { ConvertTo-GB $cs0.TotalPhysicalMemory } else { $null }
    }
}

function Get-OSInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Notes,
        [Microsoft.Management.Infrastructure.CimSession]$CimSession
    )
    $os = Invoke-CimQuerySafe -ClassName Win32_OperatingSystem -Label 'Operating system info' -Notes $Notes -CimSession $CimSession
    if (-not $os) {
        return [pscustomobject]@{
            OSName = $null; OSVersion = $null; OSBuild = $null; OSArchitecture = $null
            OSInstallDate = $null; LastBootTime = $null; UptimeDays = $null
        }
    }
    $o = $os[0]
    $uptime = $null
    if ($o.LastBootUpTime -and $o.LocalDateTime) {
        $uptime = [math]::Round(($o.LocalDateTime - $o.LastBootUpTime).TotalDays, 2)
    }
    [pscustomobject]@{
        OSName         = $o.Caption
        OSVersion      = $o.Version
        OSBuild        = $o.BuildNumber
        OSArchitecture = $o.OSArchitecture
        OSInstallDate  = if ($o.InstallDate)    { $o.InstallDate.ToString('yyyy-MM-dd') } else { $null }
        LastBootTime   = if ($o.LastBootUpTime) { $o.LastBootUpTime.ToString('yyyy-MM-dd HH:mm') } else { $null }
        UptimeDays     = $uptime
    }
}

function Get-DiskInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Notes,
        [Microsoft.Management.Infrastructure.CimSession]$CimSession
    )
    $logical  = New-Object 'System.Collections.Generic.List[object]'
    $physical = New-Object 'System.Collections.Generic.List[object]'

    # DriveType 3 = local fixed disk
    $volumes = Invoke-CimQuerySafe -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -Label 'Logical disk info' -Notes $Notes -CimSession $CimSession
    foreach ($v in @($volumes)) {
        if ($null -eq $v) { continue }
        $pctFree = $null; $used = $null
        if ($v.Size -and $v.Size -gt 0) {
            $pctFree = [math]::Round(($v.FreeSpace / $v.Size) * 100, 1)
            $used    = ConvertTo-GB ($v.Size - $v.FreeSpace)
        }
        $logical.Add([pscustomobject]@{
            ComputerName = $ComputerName
            DriveLetter  = $v.DeviceID
            VolumeLabel  = $v.VolumeName
            FileSystem   = $v.FileSystem
            SizeGB       = ConvertTo-GB $v.Size
            UsedGB       = $used
            FreeGB       = ConvertTo-GB $v.FreeSpace
            PercentFree  = $pctFree
        })
    }

    $drives = Invoke-CimQuerySafe -ClassName Win32_DiskDrive -Label 'Physical disk info' -Notes $Notes -CimSession $CimSession
    foreach ($d in @($drives)) {
        if ($null -eq $d) { continue }
        $physical.Add([pscustomobject]@{
            ComputerName   = $ComputerName
            DiskIndex      = $d.Index
            Model          = $d.Model
            SerialNumber   = ConvertTo-CleanSerial -Value $d.SerialNumber
            Firmware       = $d.FirmwareRevision
            InterfaceType  = $d.InterfaceType
            MediaType      = $d.MediaType
            SizeGB         = ConvertTo-GB $d.Size
            PartitionCount = $d.Partitions
            Status         = $d.Status
        })
    }

    [pscustomobject]@{ Logical = $logical.ToArray(); Physical = $physical.ToArray() }
}

function Get-SoftwareInventory {
    <# Reads machine-wide Uninstall registry keys (read-only; does NOT use Win32_Product,
       which can trigger MSI repair/reconfiguration). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][bool]$IsLocal,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Notes,
        [pscredential]$Credential,
        [int]$TimeoutSeconds = 30
    )
    $reader = {
        $paths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($path in $paths) {
            $arch = if ($path -like '*WOW6432Node*') { '32-bit' } else { 'Native' }
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -and
                               -not ($_.PSObject.Properties['SystemComponent'] -and $_.SystemComponent -eq 1) } |
                ForEach-Object {
                    [pscustomobject]@{
                        Name        = [string]$_.DisplayName
                        Version     = if ($_.PSObject.Properties['DisplayVersion']) { [string]$_.DisplayVersion } else { $null }
                        Publisher   = if ($_.PSObject.Properties['Publisher'])      { [string]$_.Publisher } else { $null }
                        InstallDate = if ($_.PSObject.Properties['InstallDate'])    { [string]$_.InstallDate } else { $null }
                        Architecture = $arch
                    }
                }
        }
    }

    try {
        if ($IsLocal) {
            $raw = @(& $reader)
        }
        else {
            $invoke = @{ ComputerName = $ComputerName; ScriptBlock = $reader; ErrorAction = 'Stop' }
            if ($Credential) { $invoke['Credential'] = $Credential }
            $raw = @(Invoke-Command @invoke)
        }
    }
    catch {
        $Notes.Add("Installed software unavailable: $($_.Exception.Message.Trim()) (remote software inventory requires WinRM/PowerShell remoting)")
        return @()
    }

    $raw | Sort-Object Name, Version -Unique | ForEach-Object {
        [pscustomobject]@{
            ComputerName = $ComputerName
            Name         = $_.Name
            Version      = $_.Version
            Publisher    = $_.Publisher
            InstallDate  = $_.InstallDate
            Architecture = $_.Architecture
        }
    }
}

#endregion

#region Orchestration

function Get-SystemInventory {
    <# Collects everything for one computer and returns an Inventory.Result object. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$Credential,
        [int]$TimeoutSeconds = 30,
        [switch]$SkipSoftware
    )
    $notes     = New-Object 'System.Collections.Generic.List[string]'
    $isLocal   = Test-IsLocalComputer -ComputerName $ComputerName
    $session   = $null
    $connected = $true
    $hw = $null; $os = $null; $disks = $null; $software = @()

    try {
        if ($isLocal) {
            if ($Credential) { Write-Verbose "[$ComputerName] -Credential is ignored for the local computer." }
        }
        else {
            try {
                Write-Verbose "[$ComputerName] Opening CIM session..."
                $session = New-InventorySession -ComputerName $ComputerName -Credential $Credential -TimeoutSeconds $TimeoutSeconds
            }
            catch {
                $connected = $false
                $notes.Add("Could not connect: $($_.Exception.Message.Trim())")
            }
        }

        if ($connected) {
            Write-Verbose "[$ComputerName] Collecting hardware, OS and disk data..."
            $hw    = Get-HardwareInventory -Notes $notes -CimSession $session
            $os    = Get-OSInventory       -Notes $notes -CimSession $session
            $disks = Get-DiskInventory     -ComputerName $ComputerName -Notes $notes -CimSession $session
            if (-not $SkipSoftware) {
                Write-Verbose "[$ComputerName] Collecting installed software..."
                $software = @(Get-SoftwareInventory -ComputerName $ComputerName -IsLocal $isLocal -Notes $notes `
                                -Credential $Credential -TimeoutSeconds $TimeoutSeconds)
            }
        }
    }
    catch {
        $notes.Add("Unexpected error: $($_.Exception.Message.Trim())")
    }
    finally {
        if ($session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
    }

    $status = if (-not $connected) { 'Failed' } elseif ($notes.Count -gt 0) { 'Partial' } else { 'Success' }
    foreach ($n in $notes) { Write-Warning "[$ComputerName] $n" }

    $summary = [pscustomobject][ordered]@{
        ComputerName      = $ComputerName
        CollectedAt       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Status            = $status
        Manufacturer      = if ($hw) { $hw.Manufacturer } else { $null }
        Model             = if ($hw) { $hw.Model } else { $null }
        SerialNumber      = if ($hw) { $hw.SerialNumber } else { $null }
        BaseboardSerial   = if ($hw) { $hw.BaseboardSerial } else { $null }
        BiosVersion       = if ($hw) { $hw.BiosVersion } else { $null }
        BiosReleaseDate   = if ($hw) { $hw.BiosReleaseDate } else { $null }
        ProcessorName     = if ($hw) { $hw.ProcessorName } else { $null }
        ProcessorCores    = if ($hw) { $hw.ProcessorCores } else { $null }
        LogicalProcessors = if ($hw) { $hw.LogicalProcessors } else { $null }
        TotalMemoryGB     = if ($hw) { $hw.TotalMemoryGB } else { $null }
        OSName            = if ($os) { $os.OSName } else { $null }
        OSVersion         = if ($os) { $os.OSVersion } else { $null }
        OSBuild           = if ($os) { $os.OSBuild } else { $null }
        OSArchitecture    = if ($os) { $os.OSArchitecture } else { $null }
        OSInstallDate     = if ($os) { $os.OSInstallDate } else { $null }
        LastBootTime      = if ($os) { $os.LastBootTime } else { $null }
        UptimeDays        = if ($os) { $os.UptimeDays } else { $null }
        Domain            = if ($hw) { $hw.Domain } else { $null }
        LogicalDiskCount  = if ($disks) { @($disks.Logical).Count } else { $null }
        PhysicalDiskCount = if ($disks) { @($disks.Physical).Count } else { $null }
        SoftwareCount     = if ($SkipSoftware -or -not $connected) { $null } else { @($software).Count }
        RanElevated       = if ($isLocal) { Test-IsElevated } else { $null }
        CollectionNotes   = ($notes -join '; ')
    }

    $summary.PSObject.TypeNames.Insert(0, 'Inventory.Summary')

    $result = [pscustomobject][ordered]@{
        ComputerName  = $ComputerName
        Summary       = $summary
        LogicalDisks  = if ($disks) { $disks.Logical } else { @() }
        PhysicalDisks = if ($disks) { $disks.Physical } else { @() }
        Software      = $software
    }
    $result.PSObject.TypeNames.Insert(0, 'Inventory.Result')
    $result
}

function Export-InventoryCsv {
    <# Writes objects to CSV. Honours -WhatIf/-Confirm and never overwrites silently. #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$InputObject,
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force
    )
    if (-not $InputObject -or $InputObject.Count -eq 0) {
        Write-Verbose "No rows for '$Path'; file not created."
        return $null
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Write CSV file')) {
        if ((Test-Path -LiteralPath $Path) -and -not $Force) {
            if (-not $PSCmdlet.ShouldContinue("'$Path' already exists. Overwrite it?", 'Confirm overwrite')) {
                Write-Warning "Skipped existing file: $Path"
                return $null
            }
        }
        try {
            $InputObject | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            return (Get-Item -LiteralPath $Path)
        }
        catch {
            Write-Warning "Could not write '$Path': $($_.Exception.Message.Trim())"
            return $null
        }
    }
    return $null
}

#endregion

#region Main

if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    throw 'This script collects Windows (CIM/WMI and registry) data and must run on Windows.'
}

# Resolve and prepare the output folder.
$resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) {
    throw "OutputDirectory '$resolvedOutput' is an existing file, not a folder."
}
$canWrite = $true
if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Container)) {
    if ($PSCmdlet.ShouldProcess($resolvedOutput, 'Create output folder')) {
        try { New-Item -ItemType Directory -Path $resolvedOutput -ErrorAction Stop | Out-Null }
        catch {
            throw "Cannot create output folder '$resolvedOutput': $($_.Exception.Message.Trim())"
        }
    }
    else {
        $canWrite = $false   # -WhatIf or user declined
    }
}

$results = foreach ($name in ($ComputerName | Select-Object -Unique)) {
    Get-SystemInventory -ComputerName $name -Credential $Credential `
        -TimeoutSeconds $TimeoutSeconds -SkipSoftware:$SkipSoftware
}
$results = @($results)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$exports = @(
    @{ Label = 'Summary';       Rows = @($results | ForEach-Object { $_.Summary }) }
    @{ Label = 'LogicalDisks';  Rows = @($results | ForEach-Object { $_.LogicalDisks }) }
    @{ Label = 'PhysicalDisks'; Rows = @($results | ForEach-Object { $_.PhysicalDisks }) }
    @{ Label = 'Software';      Rows = @($results | ForEach-Object { $_.Software }) }
)

$written = New-Object 'System.Collections.Generic.List[string]'
foreach ($e in $exports) {
    $file = Join-Path -Path $resolvedOutput -ChildPath ("Inventory_{0}_{1}.csv" -f $e.Label, $stamp)
    if ($canWrite -or $WhatIfPreference) {
        $item = Export-InventoryCsv -InputObject $e.Rows -Path $file -Force:$Force
        if ($item) { $written.Add($item.FullName) }
    }
}

if ($written.Count -gt 0) {
    Write-Host "Inventory exported ($($written.Count) file(s)):"
    $written | ForEach-Object { Write-Host "  $_" }
}
$failed = @($results | Where-Object { $_.Summary.Status -eq 'Failed' })
if ($failed.Count -gt 0) {
    Write-Warning ("{0} of {1} computer(s) could not be inventoried: {2}" -f $failed.Count, $results.Count, ($failed.ComputerName -join ', '))
}

# Structured output for the pipeline.
if ($PassThru) { $results } else { $results | ForEach-Object { $_.Summary } }

#endregion