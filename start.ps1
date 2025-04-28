<#
.SYNOPSIS
  Randomly switches the local network adapter IPv4 address at a configurable interval.
.PARAMETER Interval
  Interval in seconds between IP switches. Default: 60
.PARAMETER PrefixLength
  Subnet prefix length (e.g., 24 for 255.255.255.0). Default: 24
.PARAMETER Gateway
  Default gateway IP address. Default: 120.96.54.254
.PARAMETER DnsServers
  Array of DNS server IP addresses. Default: 120.96.35.1,120.96.36.1
#>
param(
  [int]$Interval = 60,
  [int]$PrefixLength = 24,
  [string]$Gateway = '120.96.54.254',
  [string[]]$DnsServers = @('120.96.35.1','120.96.36.1')
)

# Elevate to Administrator if needed
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()`
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Start-Process -FilePath PowerShell.exe `
    -Verb RunAs `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" 
  exit
}

# Select first active physical adapter (exclude virtual)
$adapter = Get-NetAdapter -Physical `
  | Where-Object Status -Eq 'Up' `
  | Where-Object InterfaceDescription -NotMatch 'Tailscale|Hyper-V' `
  | Select-Object -First 1

if (-not $adapter) {
  Write-Error 'No active physical network adapter found.'
  exit 1
}
$ifIndex = $adapter.InterfaceIndex
Write-Host "Using adapter: $($adapter.Name) (Index $ifIndex)"

while ($true) {
  # Pick a random free IP (limit to 50 attempts)
  $attempt = 0
  do {
    if (++$attempt -gt 50) {
      Write-Error 'Unable to find a free IP after 50 attempts.'
      exit 1
    }
    $octet  = Get-Random -Minimum 2 -Maximum 255
    $newIP  = "120.96.54.$octet"
    Write-Host "Checking $newIP..."
    $inUse  = (ping.exe -n 1 -w 500 $newIP | Select-String 'TTL=').Length -ne 0
  } while ($inUse)

  # Remove existing IPv4 addresses
  Write-Host 'Removing old IPv4 addresses...'
  Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 `
    | Remove-NetIPAddress -Confirm:$false

  # Remove existing default route if any
  Write-Host 'Removing old default route...'
  Remove-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue

  # Assign new static IP and gateway
  Write-Host "Assigning new IP $newIP/$PrefixLength via gateway $Gateway..."
  New-NetIPAddress `
    -InterfaceIndex  $ifIndex `
    -IPAddress       $newIP `
    -PrefixLength    $PrefixLength `
    -DefaultGateway  $Gateway

  # Configure DNS servers
  Write-Host "Setting DNS servers: $($DnsServers -join ', ')"
  Set-DnsClientServerAddress `
    -InterfaceIndex  $ifIndex `
    -ServerAddresses $DnsServers

  Write-Host "✅ Switched to IP $newIP"

  # Wait for the specified interval before next switch
  Start-Sleep -Seconds $Interval
}