<#
NOTES
    Works on Windows PowerShell 5.1 and PowerShell 7+.
    Targets need WinRM enabled  or RPC/DCOM and the
    account used needs admin rights on them. Queries run concurrently across all
    reachable machines with CIM sessions.
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [string]$ComputerListPath,

    [pscredential]$Credential,

    [string]$OutputPath = (Get-Location).Path,

    # Retry over DCOM when WinRM is unavailable on a target
    [switch]$FallbackToDcom,

    [ValidateRange(5, 600)]
    [int]$TimeoutSec = 30
)

function Test-IsLocal {
    param([string]$Name)
    $Name -in @('.', 'localhost', '127.0.0.1', $env:COMPUTERNAME)
}

function ConvertTo-TargetKey {
    # Normalises the PSComputerName CIM returns so results map back to targets
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or (Test-IsLocal $Name)) { return $env:COMPUTERNAME }
    $Name
}

# ---- Build the target list
$targets = @()
# The local-machine default only applies when no list file is given
if ($PSBoundParameters.ContainsKey('ComputerName') -or -not $ComputerListPath) {
    $targets += $ComputerName
}
if ($ComputerListPath) {
    if (-not (Test-Path $ComputerListPath)) {
        Write-Error "Computer list not found: $ComputerListPath"
        return
    }
    $targets += Get-Content $ComputerListPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}
# Group-Object is case-insensitive and keeps first-seen order, matching the hashtables used below
$targets = @($targets |
    Where-Object { $_ } |
    ForEach-Object { ConvertTo-TargetKey $_ } |
    Group-Object |
    ForEach-Object { $_.Name })

if (-not $targets) {
    Write-Error 'No computer names supplied.'
    return
}

# ---- Open sessions
$sessions = @{}   # target -> CimSession
$failures = @{}   # target -> error text

foreach ($t in $targets) {
    try {
        if (Test-IsLocal $t) {
            $sessions[$t] = New-CimSession -OperationTimeoutSec $TimeoutSec -ErrorAction Stop
            continue
        }

        $p = @{ ComputerName = $t; OperationTimeoutSec = $TimeoutSec; ErrorAction = 'Stop' }
        if ($Credential) { $p.Credential = $Credential }

        $s = $null
        try {
            $s = New-CimSession @p
            # New-CimSession can succeed without contacting the host, so probe it
            # when a fallback is possible; otherwise the failure would surface too late.
            if ($FallbackToDcom) {
                $null = Get-CimInstance -CimSession $s -ClassName Win32_OperatingSystem -OperationTimeoutSec $TimeoutSec -ErrorAction Stop
            }
            $sessions[$t] = $s
        }
        catch {
            if (-not $FallbackToDcom) { throw }
            if ($s) { Remove-CimSession -CimSession $s -ErrorAction SilentlyContinue }
            Write-Verbose "WinRM failed for $t, retrying over DCOM."
            $p.SessionOption = New-CimSessionOption -Protocol Dcom
            $sessions[$t] = New-CimSession @p
        }
    }
    catch {
        $failures[$t] = $_.Exception.Message
        Write-Warning "Could not connect to ${t}: $($_.Exception.Message)"
    }
}

# ---- Query every session concurrently
$byHost = @{}   # target -> collected data

if ($sessions.Count -gt 0) {
    $sessionList = @($sessions.Values)
    $queryErrors = @()
    $q = @{
        CimSession          = $sessionList
        OperationTimeoutSec = $TimeoutSec
        ErrorAction         = 'SilentlyContinue'
        ErrorVariable       = '+queryErrors'   # '+' appends across the four queries instead of overwriting
    }

    try {
        $osAll    = Get-CimInstance -ClassName Win32_OperatingSystem @q
        $csAll    = Get-CimInstance -ClassName Win32_ComputerSystem @q
        $cpuAll   = Get-CimInstance -ClassName Win32_Processor @q
        $diskAll  = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' @q
    }
    finally {
        $sessionList | Remove-CimSession -ErrorAction SilentlyContinue
    }

    $osMap   = @{}; foreach ($o in $osAll)  { $osMap[(ConvertTo-TargetKey $o.PSComputerName)] = $o }
    $csMap   = @{}; foreach ($c in $csAll)  { $csMap[(ConvertTo-TargetKey $c.PSComputerName)] = $c }
    $cpuMap  = @{}; foreach ($g in ($cpuAll | Group-Object { ConvertTo-TargetKey $_.PSComputerName })) { $cpuMap[$g.Name] = @($g.Group) }
    $diskMap = @{}; foreach ($g in ($diskAll | Group-Object { ConvertTo-TargetKey $_.PSComputerName })) { $diskMap[$g.Name] = $g.Group }

    foreach ($t in $sessions.Keys) {
        $os = $osMap[$t]; $cs = $csMap[$t]; $cpu = $cpuMap[$t]

        if (-not $os -or -not $cs) {
            $msg = ($queryErrors | Where-Object { $_.Exception.Message -match [regex]::Escape($t) } |
                    Select-Object -First 1 -ExpandProperty Exception).Message
            $failures[$t] = if ($msg) { $msg } else { 'No data returned (host unreachable or access denied).' }
            Write-Warning "Failed to query ${t}: $($failures[$t])"
            continue
        }

        # Use the remote machine's own clock so clock skew / time zones don't distort uptime
        $uptime = $os.LocalDateTime - $os.LastBootUpTime

        $disks = foreach ($d in $diskMap[$t]) {
            $size = [math]::Round($d.Size / 1GB, 2)
            $free = [math]::Round($d.FreeSpace / 1GB, 2)
            [pscustomobject]@{
                Drive   = $d.DeviceID
                SizeGB  = $size
                FreeGB  = $free
                FreePct = if ($size -gt 0) { [math]::Round(($free / $size) * 100, 1) } else { 0 }
            }
        }

        $byHost[$t] = [pscustomobject]@{
            Hostname     = $os.CSName
            OS           = "$($os.Caption) (Build $($os.BuildNumber), $($os.OSArchitecture))"
            CPU          = if ($cpu) { ($cpu[0].Name -replace '\s+', ' ').Trim() } else { '' }
            Cores        = if ($cpu) { ($cpu | Measure-Object -Property NumberOfCores -Sum).Sum } else { $null }
            LogicalCPUs  = if ($cpu) { ($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum } else { $null }
            TotalRAMGB   = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            FreeRAMGB    = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 2)
            Uptime       = '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
            LastBoot     = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')
            LoggedInUser = if ($cs.UserName) { $cs.UserName } else { 'No interactive user' }
            Disks        = @($disks)
        }
    }
}

# ---- Consolidate into one CSV
$collected = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

$csvRows = foreach ($t in $targets) {
    if ($byHost.ContainsKey($t)) {
        $r = $byHost[$t]
        $diskRows = if ($r.Disks.Count -gt 0) { $r.Disks } else { @([pscustomobject]@{ Drive = ''; SizeGB = $null; FreeGB = $null; FreePct = $null }) }
        foreach ($d in $diskRows) {
            [pscustomobject]@{
                Target       = $t
                Status       = 'OK'
                Hostname     = $r.Hostname
                OS           = $r.OS
                CPU          = $r.CPU
                Cores        = $r.Cores
                LogicalCPUs  = $r.LogicalCPUs
                TotalRAMGB   = $r.TotalRAMGB
                FreeRAMGB    = $r.FreeRAMGB
                Drive        = $d.Drive
                DiskSizeGB   = $d.SizeGB
                DiskFreeGB   = $d.FreeGB
                DiskFreePct  = $d.FreePct
                Uptime       = $r.Uptime
                LastBoot     = $r.LastBoot
                LoggedInUser = $r.LoggedInUser
                Collected    = $collected
                Error        = ''
            }
        }
    }
    else {
        # Keep failed machines in the report so nothing silently disappears
        [pscustomobject]@{
            Target = $t; Status = 'FAILED'; Hostname = ''; OS = ''; CPU = ''
            Cores = $null; LogicalCPUs = $null; TotalRAMGB = $null; FreeRAMGB = $null
            Drive = ''; DiskSizeGB = $null; DiskFreeGB = $null; DiskFreePct = $null
            Uptime = ''; LastBoot = ''; LoggedInUser = ''
            Collected = $collected; Error = $failures[$t]
        }
    }
}

if (-not $byHost.Count) {
    Write-Warning 'No machine returned data; the CSV will only list failures.'
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $OutputPath "SystemReport_$stamp.csv"
$csvRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host ("Queried {0} machine(s): {1} OK, {2} failed" -f $targets.Count, $byHost.Count, ($targets.Count - $byHost.Count)) -ForegroundColor Cyan
Write-Host "CSV report:  $csvPath" -ForegroundColor Green
