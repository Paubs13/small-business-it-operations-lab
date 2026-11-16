<#
.SYNOPSIS
    Reports network adapter configuration, gateway, DNS, host reachability and TCP port connectivity.

.PARAMETER Target
    Host names or IP addresses to resolve, ping and (with -Port) test over TCP.

.PARAMETER Port
    TCP ports (1-65535) to test on every target.

.PARAMETER TimeoutMs
    Per-attempt timeout for ping and TCP connects, in milliseconds (100-60000).

.PARAMETER PingCount
    Echo requests sent per host (1-10).

.PARAMETER IncludeDisconnected
    Also report adapters that are not 'Up'.

.PARAMETER TestDnsServerPort
    Also test TCP/53 on each configured DNS server.

.PARAMETER FlushDnsCache
    Clears the DNS client cache before the DNS tests. Requires elevation; asks for confirmation.

.PARAMETER OutputFormat
    Object (default), Json or Text. Object emits the structured report to the pipeline.

.PARAMETER Path
    Optional file to also save the report to (JSON for Object/Json, plain text for Text).

.EXAMPLE
    .\Get-NetworkDiagnostics.ps1

.EXAMPLE
    .\Get-NetworkDiagnostics.ps1 -Target example.com,1.1.1.1 -Port 22,443 -OutputFormat Text

.EXAMPLE
    $r = .\Get-NetworkDiagnostics.ps1 -Port 443; $r.TcpTests | Where-Object Status -ne 'Open'

.EXAMPLE
    .\Get-NetworkDiagnostics.ps1 -FlushDnsCache -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$Target = @('www.microsoft.com', 'one.one.one.one'),

    [ValidateRange(1, 65535)]
    [int[]]$Port = @(80, 443),

    [ValidateRange(100, 60000)]
    [int]$TimeoutMs = 2000,

    [ValidateRange(1, 10)]
    [int]$PingCount = 2,

    [switch]$IncludeDisconnected,
    [switch]$TestDnsServerPort,
    [switch]$FlushDnsCache,

    [ValidateSet('Object', 'Json', 'Text')]
    [string]$OutputFormat = 'Object',

    [string]$Path
)

$script:Notes = New-Object System.Collections.Generic.List[string]

function Add-Note {
    param([Parameter(Mandatory)][string]$Message)
    $script:Notes.Add($Message)
    Write-Verbose $Message
}

function Get-InnermostException {
    param([Parameter(Mandatory)][System.Exception]$Exception)
    $ex = $Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    return $ex
}

function Assert-SupportedPlatform {
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        throw 'This script uses Windows networking cmdlets and only supports Windows.'
    }
}

function Test-IsAdministrator {
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-TargetName {
    <# Returns $true for a valid IP literal or DNS host name. #>
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($Name, [ref]$ip)) { return $true }
    return ([System.Uri]::CheckHostName($Name) -eq [System.UriHostNameType]::Dns)
}

function Get-AdapterConfigurationCim {
    <# Fallback when the NetTCPIP cmdlets are unavailable. Fewer details (no link speed/MAC status). #>
    try {
        $configs = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' -ErrorAction Stop)
    }
    catch {
        Add-Note "CIM fallback failed: $((Get-InnermostException $_.Exception).Message)"
        return @()
    }
    foreach ($c in $configs) {
        $addresses = @($c.IPAddress)
        [pscustomobject]@{
            Name            = $c.Description
            Description     = $c.Description
            InterfaceIndex  = $c.InterfaceIndex
            Status          = 'Up'
            MacAddress      = $c.MACAddress
            LinkSpeed       = $null
            Dhcp            = if ($c.DHCPEnabled) { 'Enabled' } else { 'Disabled' }
            IPv4Address     = @($addresses | Where-Object { $_ -and $_ -notlike '*:*' })
            PrefixLength    = $null
            IPv6Address     = @($addresses | Where-Object { $_ -like '*:*' })
            DefaultGateway  = @($c.DefaultIPGateway | Where-Object { $_ })
            DnsServers      = @($c.DNSServerSearchOrder | Where-Object { $_ })
        }
    }
}

function Get-AdapterConfiguration {
    [CmdletBinding()]
    param([switch]$IncludeDisconnected)

    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop)
    }
    catch {
        Add-Note "Get-NetAdapter unavailable ($((Get-InnermostException $_.Exception).Message)); using CIM fallback with fewer details."
        return @(Get-AdapterConfigurationCim)
    }

    if (-not $IncludeDisconnected) {
        $adapters = @($adapters | Where-Object { $_.Status -eq 'Up' })
    }

    foreach ($adapter in $adapters) {
        $ipv4 = @(); $ipv6 = @(); $gateway = @(); $dns = @(); $prefix = $null; $dhcp = $null

        try {
            $cfg = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction Stop
            $ipv4    = @($cfg.IPv4Address | ForEach-Object { $_.IPAddress })
            $prefix  = ($cfg.IPv4Address | Select-Object -First 1).PrefixLength
            $ipv6    = @($cfg.IPv6Address | ForEach-Object { $_.IPAddress })
            $gateway = @($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) +
                       @($cfg.IPv6DefaultGateway | ForEach-Object { $_.NextHop })
            $gateway = @($gateway | Where-Object { $_ })
            $dns     = @($cfg.DNSServer | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        }
        catch {
            Add-Note "IP configuration for '$($adapter.Name)' unavailable: $((Get-InnermostException $_.Exception).Message)"
        }

        try {
            $dhcp = [string](Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop).Dhcp
        }
        catch {
            Add-Note "DHCP state for '$($adapter.Name)' unavailable: $((Get-InnermostException $_.Exception).Message)"
        }

        [pscustomobject]@{
            Name            = $adapter.Name
            Description     = $adapter.InterfaceDescription
            InterfaceIndex  = $adapter.ifIndex
            Status          = [string]$adapter.Status
            MacAddress      = $adapter.MacAddress
            LinkSpeed       = $adapter.LinkSpeed
            Dhcp            = $dhcp
            IPv4Address     = $ipv4
            PrefixLength    = $prefix
            IPv6Address     = $ipv6
            DefaultGateway  = $gateway
            DnsServers      = $dns
        }
    }
}

function Test-HostReachability {
    <# ICMP echo test. Many hosts block ICMP, so a failure is not proof the host is down. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Target,
        [ValidateRange(1, 10)][int]$Count = 2,
        [ValidateRange(100, 60000)][int]$TimeoutMs = 2000
    )

    $sent = 0; $received = 0; $rtts = @(); $lastError = $null; $address = $null
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            $sent++
            try {
                $reply = $ping.Send($Target, $TimeoutMs)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $received++
                    $rtts += $reply.RoundtripTime
                    $address = $reply.Address.ToString()
                }
                else {
                    $lastError = [string]$reply.Status
                }
            }
            catch {
                $lastError = (Get-InnermostException $_.Exception).Message
            }
        }
    }
    finally {
        $ping.Dispose()
    }

    $avg = $null
    if ($rtts.Count -gt 0) { $avg = [math]::Round(($rtts | Measure-Object -Average).Average, 1) }

    [pscustomobject]@{
        Target      = $Target
        Address     = $address
        Success     = ($received -gt 0)
        Sent        = $sent
        Received    = $received
        LossPercent = [math]::Round((($sent - $received) / [math]::Max($sent, 1)) * 100, 0)
        AvgRttMs    = $avg
        Error       = if ($received -gt 0) { $null } else { $lastError }
    }
}

function Test-DnsResolution {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Name)

    $hasResolveDnsName = [bool](Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue)

    foreach ($n in $Name) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $addresses = @(); $err = $null; $method = $null
        $ip = $null

        if ([System.Net.IPAddress]::TryParse($n, [ref]$ip)) {
            $addresses = @($n); $method = 'Literal'
        }
        else {
            try {
                if ($hasResolveDnsName) {
                    $method = 'Resolve-DnsName'
                    $addresses = @(Resolve-DnsName -Name $n -DnsOnly -ErrorAction Stop |
                        Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress })
                }
                else {
                    $method = '.NET Dns'
                    $addresses = @([System.Net.Dns]::GetHostAddresses($n) | ForEach-Object { $_.ToString() })
                }
                if ($addresses.Count -eq 0) { $err = 'Lookup succeeded but returned no address records.' }
            }
            catch {
                $err = (Get-InnermostException $_.Exception).Message
            }
        }
        $sw.Stop()

        [pscustomobject]@{
            Name      = $n
            Resolved  = ($addresses.Count -gt 0)
            Addresses = $addresses
            Method    = $method
            ElapsedMs = $sw.ElapsedMilliseconds
            Error     = $err
        }
    }
}

function Test-TcpPortConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Target,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
        [ValidateRange(100, 60000)][int]$TimeoutMs = 2000
    )

    $status = 'Error'; $err = $null
    $client = New-Object System.Net.Sockets.TcpClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $task = $client.ConnectAsync($Target, $Port)
        if ($task.Wait($TimeoutMs)) {
            if ($client.Connected) { $status = 'Open' } else { $status = 'Closed'; $err = 'Connection not established.' }
        }
        else {
            $status = 'TimedOut'
            $err = "No response within $TimeoutMs ms (filtered by a firewall or host unreachable)."
        }
    }
    catch {
        $ex = Get-InnermostException $_.Exception
        $err = $ex.Message
        if ($ex -is [System.Net.Sockets.SocketException]) {
            switch ($ex.SocketErrorCode.ToString()) {
                'ConnectionRefused' { $status = 'Refused' }
                'HostNotFound'      { $status = 'DnsFailure' }
                'TryAgain'          { $status = 'DnsFailure' }
                'NetworkUnreachable' { $status = 'Unreachable' }
                'HostUnreachable'   { $status = 'Unreachable' }
                default             { $status = 'Error' }
            }
        }
    }
    finally {
        $sw.Stop()
        $client.Dispose()
    }

    [pscustomobject]@{
        Target    = $Target
        Port      = $Port
        Status    = $status
        Open      = ($status -eq 'Open')
        ElapsedMs = $sw.ElapsedMilliseconds
        Error     = $err
    }
}

function Invoke-DnsCacheFlush {
    <# Disruptive (briefly slows next lookups) and needs elevation: confirm first, never self-elevate. #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param()

    $result = [pscustomobject]@{ Requested = $true; Performed = $false; Message = $null }

    if (-not (Test-IsAdministrator)) {
        $result.Message = 'Skipped: flushing the DNS cache requires an elevated (Administrator) session. Re-run from an elevated PowerShell if you need this.'
        return $result
    }
    if ($PSCmdlet.ShouldProcess('local DNS client cache', 'Clear')) {
        try {
            Clear-DnsClientCache -ErrorAction Stop
            $result.Performed = $true
            $result.Message = 'DNS client cache cleared.'
        }
        catch {
            $result.Message = "Failed to clear DNS cache: $((Get-InnermostException $_.Exception).Message)"
        }
    }
    else {
        $result.Message = 'Skipped: not confirmed (or -WhatIf was used).'
    }
    return $result
}

function ConvertTo-TextReport {
    param([Parameter(Mandatory)]$Report)

    $join = { param($v) (@($v) -join ', ') }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Network diagnostics - $($Report.Timestamp) on $($Report.ComputerName) (elevated: $($Report.IsElevated))")

    [void]$sb.AppendLine("`n== Adapters ==")
    [void]$sb.AppendLine(($Report.Adapters | Select-Object Name, Status, LinkSpeed, Dhcp,
        @{ n = 'IPv4'; e = { & $join $_.IPv4Address } },
        @{ n = 'Gateway'; e = { & $join $_.DefaultGateway } },
        @{ n = 'DNS'; e = { & $join $_.DnsServers } } | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())

    [void]$sb.AppendLine("`n== Gateway reachability ==")
    [void]$sb.AppendLine(($Report.Gateways | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())

    [void]$sb.AppendLine("`n== DNS resolution ==")
    [void]$sb.AppendLine(($Report.DnsLookups | Select-Object Name, Resolved, ElapsedMs,
        @{ n = 'Addresses'; e = { & $join $_.Addresses } }, Error | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())

    [void]$sb.AppendLine("`n== Host reachability (ICMP) ==")
    [void]$sb.AppendLine(($Report.Reachability | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())

    [void]$sb.AppendLine("`n== TCP port tests ==")
    [void]$sb.AppendLine(($Report.TcpTests | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())

    if ($Report.DnsCacheFlush) { [void]$sb.AppendLine("`nDNS cache flush: $($Report.DnsCacheFlush.Message)") }
    if ($Report.Notes.Count -gt 0) {
        [void]$sb.AppendLine("`n== Notes ==")
        foreach ($n in $Report.Notes) { [void]$sb.AppendLine("- $n") }
    }
    return $sb.ToString()
}

function Get-NetworkDiagnosticReport {
    [CmdletBinding()]
    param(
        [string[]]$Target,
        [int[]]$Port,
        [int]$TimeoutMs,
        [int]$PingCount,
        [switch]$IncludeDisconnected,
        [switch]$TestDnsServerPort,
        $FlushResult
    )

    $adapters = @(Get-AdapterConfiguration -IncludeDisconnected:$IncludeDisconnected)
    if ($adapters.Count -eq 0) {
        Add-Note 'No adapters to report. Nothing is connected, or adapter data could not be read.'
    }

    $gatewayAddresses = @($adapters | ForEach-Object { $_.DefaultGateway } | Where-Object { $_ } | Select-Object -Unique)
    $dnsServers       = @($adapters | ForEach-Object { $_.DnsServers } | Where-Object { $_ } | Select-Object -Unique)

    if ($gatewayAddresses.Count -eq 0) { Add-Note 'No default gateway found (adapter down, or no route configured).' }
    if ($dnsServers.Count -eq 0)       { Add-Note 'No DNS servers found in the adapter configuration.' }

    $gateways = @($gatewayAddresses | ForEach-Object {
        Test-HostReachability -Target $_ -Count $PingCount -TimeoutMs $TimeoutMs
    })

    $dnsLookups   = @(Test-DnsResolution -Name $Target)
    $reachability = @($Target | ForEach-Object {
        Test-HostReachability -Target $_ -Count $PingCount -TimeoutMs $TimeoutMs
    })

    $tcpTests = @()
    foreach ($t in $Target) {
        foreach ($p in $Port) {
            $tcpTests += Test-TcpPortConnectivity -Target $t -Port $p -TimeoutMs $TimeoutMs
        }
    }
    if ($TestDnsServerPort) {
        foreach ($d in $dnsServers) {
            $tcpTests += Test-TcpPortConnectivity -Target $d -Port 53 -TimeoutMs $TimeoutMs
        }
    }

    $report = [pscustomobject]@{
        Timestamp     = (Get-Date).ToString('s')
        ComputerName  = $env:COMPUTERNAME
        IsElevated    = (Test-IsAdministrator)
        Adapters      = $adapters
        Gateways      = $gateways
        DnsServers    = $dnsServers
        DnsLookups    = $dnsLookups
        Reachability  = $reachability
        TcpTests      = $tcpTests
        DnsCacheFlush = $FlushResult
        Summary       = [pscustomobject]@{
            AdaptersReported  = $adapters.Count
            GatewaysTested    = $gateways.Count
            GatewaysReachable = @($gateways | Where-Object { $_.Success }).Count
            DnsLookupsTotal   = $dnsLookups.Count
            DnsLookupsOk      = @($dnsLookups | Where-Object { $_.Resolved }).Count
            HostsTested       = $reachability.Count
            HostsReachable    = @($reachability | Where-Object { $_.Success }).Count
            TcpTestsTotal     = $tcpTests.Count
            TcpTestsOpen      = @($tcpTests | Where-Object { $_.Open }).Count
        }
        Notes         = @($script:Notes)
    }
    $report.PSObject.TypeNames.Insert(0, 'NetworkDiagnostics.Report')
    return $report
}

# ---- Entry point (skipped when the file is dot-sourced to reuse the functions) ----
if ($MyInvocation.InvocationName -ne '.') {
    try { Assert-SupportedPlatform } catch { Write-Error $_.Exception.Message; return }

    $badTargets = @($Target | Where-Object { -not (Test-TargetName $_) })
    if ($badTargets.Count -gt 0) {
        Write-Error "Invalid target(s): $($badTargets -join ', '). Use a valid host name or IP address."
        return
    }

    if ($Path) {
        $parent = Split-Path -Path $Path -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
            Write-Error "Output folder does not exist: $parent"
            return
        }
    }

    $flushResult = $null
    if ($FlushDnsCache) { $flushResult = Invoke-DnsCacheFlush }

    $report = Get-NetworkDiagnosticReport -Target $Target -Port $Port -TimeoutMs $TimeoutMs `
        -PingCount $PingCount -IncludeDisconnected:$IncludeDisconnected `
        -TestDnsServerPort:$TestDnsServerPort -FlushResult $flushResult

    switch ($OutputFormat) {
        'Object' { $output = $report }
        'Json'   { $output = $report | ConvertTo-Json -Depth 6 }
        'Text'   { $output = ConvertTo-TextReport -Report $report }
    }

    if ($Path) {
        try {
            if ($OutputFormat -eq 'Object') { $toSave = $report | ConvertTo-Json -Depth 6 } else { $toSave = $output }
            Set-Content -LiteralPath $Path -Value $toSave -Encoding UTF8 -ErrorAction Stop
            Write-Verbose "Report saved to $Path"
        }
        catch {
            Write-Warning "Could not save report to '$Path': $((Get-InnermostException $_.Exception).Message)"
        }
    }

    $output
}