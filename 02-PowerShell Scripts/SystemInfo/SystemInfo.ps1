[CmdletBinding()]
param(
    [string]$OutputPath = (Get-Location).Path,

    [string[]]$ComputerName = $env:COMPUTERNAME
)

function Get-SystemInfo {
    param([string]$Computer)

    $cimParams = @{}
    if ($Computer -ne $env:COMPUTERNAME -and $Computer -ne 'localhost') {
        $cimParams.ComputerName = $Computer
    }

    $os   = Get-CimInstance Win32_OperatingSystem @cimParams
    $cs   = Get-CimInstance Win32_ComputerSystem @cimParams
    $cpu  = Get-CimInstance Win32_Processor @cimParams | Select-Object -First 1
    $disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' @cimParams

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeText = '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes

    $totalRam = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $freeRam  = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 2)

    $diskInfo = foreach ($d in $disks) {
        $size = [math]::Round($d.Size / 1GB, 2)
        $free = [math]::Round($d.FreeSpace / 1GB, 2)
        [pscustomobject]@{
            Drive   = $d.DeviceID
            SizeGB  = $size
            FreeGB  = $free
            FreePct = if ($size -gt 0) { [math]::Round(($free / $size) * 100, 1) } else { 0 }
        }
    }

    [pscustomobject]@{
        Hostname    = $os.CSName
        OS          = "$($os.Caption) (Build $($os.BuildNumber), $($os.OSArchitecture))"
        CPU         = ($cpu.Name -replace '\s+', ' ').Trim()
        Cores       = $cpu.NumberOfCores
        LogicalCPUs = $cpu.NumberOfLogicalProcessors
        TotalRAMGB  = $totalRam
        FreeRAMGB   = $freeRam
        Uptime      = $uptimeText
        LastBoot    = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')
        LoggedInUser = if ($cs.UserName) { $cs.UserName } else { 'No interactive user' }
        Disks       = $diskInfo
        Collected   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
}


$results = foreach ($c in $ComputerName) {
    try {
        Get-SystemInfo -Computer $c
    }
    catch {
        Write-Warning "Failed to query ${c}: $($_.Exception.Message)"
    }
}

if (-not $results) {
    Write-Error 'No data collected.'
    return
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$csvRows = foreach ($r in $results) {
    foreach ($d in $r.Disks) {
        [pscustomobject]@{
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
             Collected    = $r.Collected
            }
        }
    }
$csvPath = Join-Path $OutputPath "SystemReport_$stamp.csv"
$csvRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "CSV report:  $csvPath" -ForegroundColor Green
