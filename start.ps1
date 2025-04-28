<#
.SYNOPSIS
  Randomly switches the local network adapter IPv4 address at a configurable interval,
  saving and restoring your original settings on exit (Ctrl+C or script end),
  and displays a real-time countdown until the next switch.
.PARAMETER Prefix
  The fixed leading octets of your IP address (e.g. '192.168', '10.0.1.5', etc.).
  Must consist of 1–3 octets separated by dots. Default: '120.96.54'
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
  [ValidatePattern('^(\d{1,3}\.){0,2}\d{1,3}$')]
  [string]   $Prefix       = '120.96.54',
  [int]      $Interval     = 60,
  [int]      $PrefixLength = 24,
  [string]   $Gateway      = '120.96.54.254',
  [string[]] $DnsServers   = @('120.96.35.1','120.96.36.1')
)

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] `
      [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Elevating to Administrator..."
  Start-Process pwsh.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

# Parse and validate prefix
$fixedOctets = $Prefix.Split('.')
if ($fixedOctets.Count -ge 4) {
  Write-Error "Prefix may contain at most 3 octets."
  exit 1
}
[int]$dynamicCount = 4 - $fixedOctets.Count

# Select the first active physical adapter (exclude Tailscale/Hyper-V)
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

# Save original IP(s), default route, and DNS
$origIPs   = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4
$origRoute = Get-NetRoute     -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' | Select-Object -First 1
$origDNS   = Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4

function Restore-Original {
  Write-Host "`nRestoring original network settings..."
  # Flush current IPv4 and default route
  Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  Remove-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' `
    -Confirm:$false -ErrorAction SilentlyContinue

  # Restore original IP(s) and gateway
  foreach ($ip in $origIPs) {
    Write-Host "  Restoring IP $($ip.IPAddress)/$($ip.PrefixLength)"
    New-NetIPAddress `
      -InterfaceIndex  $ifIndex `
      -IPAddress       $ip.IPAddress `
      -PrefixLength    $ip.PrefixLength `
      -DefaultGateway  $origRoute.NextHop
  }
  # Restore DNS servers
  Write-Host "  Restoring DNS: $($origDNS.ServerAddresses -join ', ')"
  Set-DnsClientServerAddress `
    -InterfaceIndex  $ifIndex `
    -ServerAddresses $origDNS.ServerAddresses

  Write-Host "✅ Original settings restored."
}

# Trap exits/CTRl+C
if ($Host.Name -eq 'ConsoleHost' -and [Console]::CancelKeyPress) {
  Register-ObjectEvent -InputObject [Console] -EventName CancelKeyPress -Action {
    $EventArgs.Cancel = $true; Restore-Original; exit
  } | Out-Null
}

# Main rotation loop
try {
  while ($true) {
    # Generate a candidate IP
    $attempt = 0
    do {
      if (++$attempt -gt 50) {
        Write-Error "Unable to find a free IP after 50 attempts."
        break
      }
      $randomOctets = for ($i=1; $i -le $dynamicCount; $i++) {
        Get-Random -Minimum 50 -Maximum 255
      }
      $newIP = ($fixedOctets + $randomOctets) -join '.'
      Write-Host "Checking $newIP..."
      $inUse = (ping.exe -n 1 -w 500 $newIP | Select-String 'TTL=').Length -ne 0
    } while ($inUse)

    if ($attempt -gt 50) { break }

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

    # Countdown until next switch
    for ($i = 1; $i -le $Interval; $i++) {
      $percent = [int](($i / $Interval) * 100)
      Write-Progress -Activity "IP Rotation" `
                     -Status ("Next switch in {0} sec" -f ($Interval - $i)) `
                     -PercentComplete $percent
      Start-Sleep -Seconds 1
    }
    Write-Progress -Activity "IP Rotation" -Completed
  }
}
finally {
  Restore-Original
}