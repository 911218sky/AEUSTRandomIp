<#
.SYNOPSIS
  Randomly switches the local network adapter IPv4 address at a configurable interval,
  saving and restoring your original settings on exit (Ctrl+C or script end).
.PARAMETER Interval
  Seconds between IP rotations. Default: 60
.PARAMETER PrefixLength
  Subnet prefix length (e.g., 24 for 255.255.255.0). Default: 24
.PARAMETER Gateway
  Default gateway IP address. Default: 120.96.54.254
.PARAMETER DnsServers
  Array of DNS server IP addresses. Default: 120.96.35.1,120.96.36.1
#>
param(
  [int]    $Interval     = 60,
  [int]    $PrefixLength = 24,
  [string] $Gateway      = '120.96.54.254',
  [string[]]$DnsServers  = @('120.96.35.1','120.96.36.1')
)

# Elevate to Administrator if needed
if (-not ([Security.Principal.WindowsPrincipal] `
      [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Elevating to Administrator..."
  Start-Process PowerShell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

# Select first active physical adapter (exclude virtual)
$adapter = Get-NetAdapter -Physical |
           Where-Object Status -Eq 'Up' |
           Where-Object InterfaceDescription -NotMatch 'Tailscale|Hyper-V' |
           Select-Object -First 1

if (-not $adapter) {
  Write-Error "No active physical network adapter found."
  exit 1
}
$ifIndex = $adapter.InterfaceIndex
Write-Host "Using adapter: $($adapter.Name) (Index $ifIndex)"

# Save original configuration
$origIPs    = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4
$origRoute  = Get-NetRoute     -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' | Select-Object -First 1
$origDNS    = Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4

function Restore-Original {
  Write-Host "`nRestoring original network settings..."

  # 1. Flush current config
  Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  Remove-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' `
    -Confirm:$false -ErrorAction SilentlyContinue

  # 2. Restore IP(s) and route
  foreach ($ip in $origIPs) {
    Write-Host "  Restoring IP $($ip.IPAddress)/$($ip.PrefixLength)"
    New-NetIPAddress `
      -InterfaceIndex $ifIndex `
      -IPAddress      $ip.IPAddress `
      -PrefixLength   $ip.PrefixLength `
      -DefaultGateway $origRoute.NextHop
  }

  # 3. Restore DNS
  Write-Host "  Restoring DNS: $($origDNS.ServerAddresses -join ', ')"
  Set-DnsClientServerAddress `
    -InterfaceIndex  $ifIndex `
    -ServerAddresses $origDNS.ServerAddresses

  Write-Host "✅ Original settings restored."
}

# Hook Ctrl+C only in a real console host
if ($Host.Name -eq 'ConsoleHost' -and [Console]::CancelKeyPress) {
  Register-ObjectEvent -InputObject [Console] -EventName CancelKeyPress -Action {
    $EventArgs.Cancel = $true
    Restore-Original
    exit
  } | Out-Null
}

# Main loop with try/finally to ensure restore
try {
  while ($true) {
    # Find a free random IP
    $attempt = 0
    do {
      if (++$attempt -gt 50) {
        Write-Error "Unable to find a free IP after 50 attempts."
        break
      }
      $octet = Get-Random -Minimum 2 -Maximum 255
      $newIP = "120.96.54.$octet"
      Write-Host "Checking $newIP..."
      $inUse = (ping.exe -n 1 -w 500 $newIP | Select-String 'TTL=').Length -ne 0
    } while ($inUse)

    # Apply new IP, route, and DNS
    Write-Host "Flushing old IPs and routes..."
    Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 |
      Remove-NetIPAddress -Confirm:$false
    Remove-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' `
      -Confirm:$false -ErrorAction SilentlyContinue

    Write-Host "Assigning $newIP/$PrefixLength via $Gateway"
    New-NetIPAddress `
      -InterfaceIndex  $ifIndex `
      -IPAddress       $newIP `
      -PrefixLength    $PrefixLength `
      -DefaultGateway  $Gateway

    Write-Host "Setting DNS servers: $($DnsServers -join ', ')"
    Set-DnsClientServerAddress `
      -InterfaceIndex  $ifIndex `
      -ServerAddresses $DnsServers

    Write-Host "✅ Switched to $newIP"
    Start-Sleep -Seconds $Interval
  }
}
finally {
  Restore-Original
}
